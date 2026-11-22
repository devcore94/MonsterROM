import com.android.apksig.ApkVerifier;
import java.io.File;
import java.io.FileInputStream;
import java.security.cert.Certificate;
import java.security.cert.CertificateFactory;
import java.util.List;

class VerifyManifest {
    public static void main(String[] args) throws Exception {
        Certificate expected;
        try (FileInputStream in = new FileInputStream(args[2])) {
            expected = CertificateFactory.getInstance("X.509").generateCertificate(in);
        }
        ApkVerifier.Result result = new ApkVerifier.Builder(new File(args[0]))
                .setV4SignatureFile(new File(args[1])).setMinCheckedPlatformVersion(37)
                .setMaxCheckedPlatformVersion(37).build().verify();
        if (!result.isVerified() || !result.isVerifiedUsingV4Scheme()
                || !result.getSignerCertificates().equals(List.of(expected))) {
            throw new IllegalStateException("Failed to verify " + args[0] + " " + result.getErrors());
        }
    }
}
