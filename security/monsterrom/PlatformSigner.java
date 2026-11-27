import com.android.apksig.ApkSigner;
import com.android.apksig.ApkVerifier;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.security.KeyFactory;
import java.security.MessageDigest;
import java.security.PrivateKey;
import java.security.cert.CertificateFactory;
import java.security.cert.X509Certificate;
import java.security.spec.PKCS8EncodedKeySpec;
import java.util.HashSet;
import java.util.HexFormat;
import java.util.List;
import java.util.Set;
import java.util.stream.Stream;
import javax.xml.XMLConstants;
import javax.xml.parsers.DocumentBuilderFactory;
import javax.xml.transform.OutputKeys;
import javax.xml.transform.TransformerFactory;
import javax.xml.transform.dom.DOMSource;
import javax.xml.transform.stream.StreamResult;
import org.w3c.dom.Document;
import org.w3c.dom.Element;
import org.w3c.dom.Node;
import org.w3c.dom.NodeList;

public class PlatformSigner {
    // S947B ZZKN and G996B HZC2 use the same Samsung platform certificate.
    private static final String SAMSUNG = "34df0e7a9f1cf1892e45c056b4973cd81ccf148a4050d11aea4ac5a65f900a42";
    // A previous MonsterROM build signed some APEX payload apps with this
    // temporary platform certificate. Keep it in the migration set so the
    // shared-UID members are brought onto the selected target certificate.
    private static final String LEGACY_MONSTERROM = "56f3570aadd0a1ee83b63969475d5d51341d47e0c9f77104c81917f964db81a2";
    // An earlier t2s test image used the public AOSP platform certificate for
    // APKs inside the Bluetooth and NFC APEXes. Keep it in the migration set
    // so those APKs can be brought onto whichever target certificate is used.
    private static final String AOSP_PLATFORM = "c8a2e9bccf597c2fb6dc66bee293fc13f2fc47ec77bc6b2b0d52c11f51192ab8";
    // The interrupted local test build used the repository's alternate test
    // certificate before the real AOSP platform pair was restored. Migrate
    // those APKs as well instead of leaving a second platform signer behind.
    private static final String ALTERNATE_TEST = "a40da80a59d170caa950cf15c18c454d47a39b26989d8b640ecd745ba71bf5dc";
    private static final HexFormat HEX = HexFormat.of();

    static boolean isPlatformSource(String digest) {
        return digest.equals(SAMSUNG) || digest.equals(LEGACY_MONSTERROM) ||
                digest.equals(AOSP_PLATFORM) || digest.equals(ALTERNATE_TEST);
    }

    private static List<X509Certificate> verify(Path apk) throws Exception {
        ApkVerifier.Result result = new ApkVerifier.Builder(apk.toFile())
                .setMinCheckedPlatformVersion(37).setMaxCheckedPlatformVersion(37).build().verify();
        if (!result.isVerified()) {
            throw new IllegalArgumentException("Signature verification failed for " + apk + " " + result.getErrors());
        }
        return result.getSignerCertificates();
    }

    private static boolean resign(Path apk, X509Certificate local,
                                  ApkSigner.SignerConfig signer) throws Exception {
        List<X509Certificate> current = verify(apk);
        if (current.size() != 1) {
            return false;
        }
        String digest = HEX.formatHex(MessageDigest.getInstance("SHA-256")
                .digest(current.get(0).getEncoded()));
        if (!isPlatformSource(digest)) {
            return false;
        }
        Path output = Files.createTempFile(apk.getParent(), ".monsterrom-", ".tmp");
        try {
            new ApkSigner.Builder(List.of(signer))
                    .setInputApk(apk.toFile()).setOutputApk(output.toFile())
                    .setV1SigningEnabled(true).setV2SigningEnabled(true).setV3SigningEnabled(true)
                    .setV4SigningEnabled(false).setOtherSignersSignaturesPreserved(false)
                    .setAlignmentPreserved(true).setLibraryPageAlignmentBytes(16384).build().sign();
            if (!verify(output).equals(List.of(local))) {
                throw new IllegalStateException("Unexpected output signer for " + apk);
            }
            // The normal build runs on Linux, where APK mode bits are
            // preserved explicitly. Windows-hosted recovery builds can
            // reach a WSL tree through the UNC provider, which does not
            // expose POSIX permissions; the APK replacement itself remains
            // safe because it stays in the same tree and inherits its file
            // metadata from that provider.
            try {
                Files.setPosixFilePermissions(output, Files.getPosixFilePermissions(apk));
            } catch (UnsupportedOperationException ignored) {
                // No POSIX view is available on this host filesystem.
            }
            Files.move(output, apk, StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING);
            return true;
        } finally {
            Files.deleteIfExists(output);
        }
    }

    private static void updateMacPolicy(Path file, String newCert) throws Exception {
        DocumentBuilderFactory factory = DocumentBuilderFactory.newInstance();
        factory.setFeature(XMLConstants.FEATURE_SECURE_PROCESSING, true);
        factory.setFeature("http://apache.org/xml/features/disallow-doctype-decl", true);
        factory.setAttribute(XMLConstants.ACCESS_EXTERNAL_DTD, "");
        factory.setAttribute(XMLConstants.ACCESS_EXTERNAL_SCHEMA, "");
        Document policy;
        try (InputStream input = Files.newInputStream(file)) {
            policy = factory.newDocumentBuilder().parse(input);
        }

        MessageDigest sha256 = MessageDigest.getInstance("SHA-256");
        Set<String> localPackages = new HashSet<>();
        String localGlobalSeinfo = null;
        boolean changed = false;
        for (Node entry = policy.getDocumentElement().getFirstChild(); entry != null; entry = entry.getNextSibling()) {
            if (!(entry instanceof Element signer) || !signer.getTagName().equals("signer")) {
                continue;
            }
            NodeList certs = signer.getElementsByTagName("cert");
            if (certs.getLength() + (signer.hasAttribute("signature") ? 1 : 0) != 1) {
                // APK migration only handles single-signer packages. Preserve multi-signer rules.
                continue;
            }
            Element certificate = certs.getLength() == 1 ? (Element) certs.item(0) : signer;
            String oldCert = certificate.getAttribute("signature");
            if (!oldCert.equalsIgnoreCase(newCert)) {
                // Policy values are full DER certificates. Match the same sources as APK signing.
                if (!isPlatformSource(HEX.formatHex(sha256.digest(HEX.parseHex(oldCert))))) {
                    continue;
                }
                certificate.setAttribute("signature", newCert);
                changed = true;
            }

            for (Node child = signer.getFirstChild(); child != null; child = child.getNextSibling()) {
                if (!(child instanceof Element rule)) {
                    continue;
                }
                if (rule.getTagName().equals("seinfo")) {
                    if (localGlobalSeinfo != null) {
                        throw new IllegalStateException("Duplicate global rule for the selected platform signer in " + file);
                    }
                    localGlobalSeinfo = rule.getAttribute("value");
                } else if (rule.getTagName().equals("package") && !localPackages.add(rule.getAttribute("name"))) {
                    throw new IllegalStateException("Duplicate package rule for the selected platform signer in " + file);
                }
            }
        }
        if (file.getFileName().toString().equals("plat_mac_permissions.xml") && !"platform".equals(localGlobalSeinfo)) {
            throw new IllegalStateException("Missing platform role for the selected platform signer in " + file);
        }

        if (changed) {
            Path tmp = Files.createTempFile(file.getParent(), ".monsterrom-", ".tmp");
            try {
                TransformerFactory transformerFactory = TransformerFactory.newInstance();
                transformerFactory.setFeature(XMLConstants.FEATURE_SECURE_PROCESSING, true);
                transformerFactory.setAttribute(XMLConstants.ACCESS_EXTERNAL_DTD, "");
                transformerFactory.setAttribute(XMLConstants.ACCESS_EXTERNAL_STYLESHEET, "");
                var transformer = transformerFactory.newTransformer();
                if (policy.getXmlEncoding() != null) {
                    transformer.setOutputProperty(OutputKeys.ENCODING, policy.getXmlEncoding());
                }
                try (var output = Files.newOutputStream(tmp)) {
                    transformer.transform(new DOMSource(policy), new StreamResult(output));
                }
                try {
                    Files.setPosixFilePermissions(tmp, Files.getPosixFilePermissions(file));
                } catch (UnsupportedOperationException ignored) {
                    // See the corresponding APK replacement above: a
                    // Windows-hosted UNC build has no POSIX permission view.
                }
                Files.move(tmp, file, StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING);
            } finally {
                Files.deleteIfExists(tmp);
            }
            System.out.println("Updated " + file);
        }
    }

    public static void main(String[] args) throws Exception {
        if (args.length != 4) {
            throw new IllegalArgumentException("Expected stock framework-res.apk, local certificate, PKCS8 key and partition tree");
        }
        List<X509Certificate> original = verify(Path.of(args[0]));
        if (original.size() != 1 || !HEX.formatHex(MessageDigest.getInstance("SHA-256")
                .digest(original.get(0).getEncoded())).equals(SAMSUNG)) {
            throw new IllegalArgumentException("Unexpected stock platform signer");
        }
        X509Certificate local;
        try (InputStream in = Files.newInputStream(Path.of(args[1]))) {
            local = (X509Certificate) CertificateFactory.getInstance("X.509").generateCertificate(in);
        }
        String localCert = HEX.formatHex(local.getEncoded());
        PrivateKey key = KeyFactory.getInstance("RSA").generatePrivate(
                new PKCS8EncodedKeySpec(Files.readAllBytes(Path.of(args[2]))));
        ApkSigner.SignerConfig signer = new ApkSigner.SignerConfig.Builder("MONSTERROM", key, List.of(local)).build();
        Path root = Path.of(args[3]);
        List<Path> files;
        try (Stream<Path> paths = Files.walk(root)) {
            files = paths.filter(file -> Files.isRegularFile(file, LinkOption.NOFOLLOW_LINKS))
                    .filter(file -> file.toString().endsWith(".apk") || file.toString().endsWith("_mac_permissions.xml"))
                    .sorted().toList();
        }
        int signed = 0;
        for (Path file : files) {
            if (file.toString().endsWith("_mac_permissions.xml")) {
                updateMacPolicy(file, localCert);
            } else if (resign(file, local, signer)) {
                System.out.println("Signed " + root.relativize(file));
                signed++;
            }
        }
        System.out.println("Signed " + signed + " platform APKs in " + root);
    }
}
