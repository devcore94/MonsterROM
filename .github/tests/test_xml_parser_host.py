"""Firmware-free checks of the real pinned parser, cache and XML entry points."""
import copy
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import tempfile
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]
WRAPPER = ROOT / "scripts/run_xml_perl.sh"
SPEC = importlib.util.spec_from_file_location("unica_xml_setup", ROOT / "scripts/setup_xml_parser.py")
SETUP = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SETUP)
PREFIX = ROOT / "out/tools/host-perl" / SETUP.CACHE_NAME
BODIES = {
    "unica/mods/settings/customize.sh": ["8b93cd3b1b13b7fc297114ced9308be35c54d7f48542048bf62bb708ecf65acc"],
    "unica/mods/setupwizard/customize.sh": ["210255434003e14d74c1d9f9f7a3dad2d644925e89bb71bf794c6e2d80f8cf37"],
    "unica/patches/camera/customize.sh": ["a7bb27c5ba8440740138718730211bba8cce2fe12773c4940af803622704ec5f", "ba95716a8647ef1590f0d17e6d8cb5b146520b4e4d7f823f04f5d5527b5f027e"],
    "unica/patches/rro/customize.sh": ["2146265e50dc6ebfe8ce59a93d12990747b6ed0114abc0da415e7ddfb8faa6c2"],
    "unica/patches/spen/customize.sh": ["aed2a9fcd83bf09c67b8aa4ecdb5242bf6eba72186e43d009af91d55bfbc379f"],
    "unica/patches/bluetooth/customize.sh": ["34c59cc661b46f509d70a40a98e0d8c09470f43be1a69ff5512030757f735f4f"],
}


def snapshot(root):
    return {p.relative_to(root).as_posix(): (p.read_bytes(), p.stat().st_mtime_ns)
            for p in root.rglob("*") if p.is_file() and not p.is_symlink()}


class XmlParserHostTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Missing prerequisites are failures, not silently skipped regressions.
        SETUP.check(PREFIX)

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="xml-parser-host-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.tools = self.root / "tools with spaces"
        self.prefix = self.tools / "host-perl" / SETUP.CACHE_NAME
        shutil.copytree(PREFIX, self.prefix)
        self.receipt = json.loads((self.prefix / "receipt.json").read_text())
        self.env = dict(os.environ, TOOLS_DIR=str(self.tools), PYTHONDONTWRITEBYTECODE="1")

    def save_receipt(self):
        (self.prefix / "receipt.json").write_text(json.dumps(self.receipt))

    def rejected(self):
        before = snapshot(self.prefix)
        with mock.patch.object(SETUP.urllib.request, "urlopen", side_effect=AssertionError("network")):
            for action in (SETUP.check, SETUP.install):
                with self.assertRaises((ValueError, OSError)):
                    action(self.prefix)
        self.assertEqual(snapshot(self.prefix), before, "No repair or receipt refresh is allowed")

    def test_valid_cache_is_checked_offline_and_reused_without_rebuilding(self):
        before = snapshot(self.prefix)
        with mock.patch.object(SETUP.urllib.request, "urlopen", side_effect=AssertionError("network")), \
                mock.patch.object(SETUP.subprocess, "run", wraps=subprocess.run) as commands:
            SETUP.check(self.prefix)
            SETUP.install(self.prefix)
        self.assertTrue(all(call.args[0][0] == str(self.prefix / "bin/perl") for call in commands.call_args_list))
        self.assertEqual(snapshot(self.prefix), before)

    def test_missing_cache_check_never_creates_or_downloads_anything(self):
        absent = self.root / "absent/host-perl/xml-parser-2.59"
        with mock.patch.object(SETUP.urllib.request, "urlopen", side_effect=AssertionError("network")):
            with self.assertRaises(ValueError):
                SETUP.check(absent)
        self.assertFalse(absent.parent.exists())

    def test_provisioning_does_not_inherit_test_bypass_or_perl_injection_options(self):
        poisoned = {"MAKEFLAGS": "-i", "MFLAGS": "-n", "GNUMAKEFLAGS": "-i", "HARNESS_OPTIONS": "bad",
                    "HARNESS_PERL_SWITCHES": "-MEvil", "HARNESS_SUBCLASS": "Evil", "PERL5OPT": "-MEvil",
                    "PERL_UNICODE": "SDA", "PERLIO": "bad", "PERL_MM_OPT": "bad"}
        with mock.patch.dict(os.environ, poisoned):
            env = SETUP.environment(self.prefix / "lib/perl5")
        self.assertTrue(set(poisoned).isdisjoint(env))

    def test_missing_receipt_is_not_automatically_refreshed(self):
        (self.prefix / "receipt.json").unlink()
        self.rejected()

    def test_malformed_receipt_is_not_repaired(self):
        (self.prefix / "receipt.json").write_text("{not JSON")
        self.rejected()

    def test_duplicate_top_level_and_nested_receipt_keys_are_rejected(self):
        for text in ('{"schema":1,"schema":1}', '{"files":{"x":"1","x":"2"}}'):
            with self.subTest(text=text):
                (self.prefix / "receipt.json").write_text(text)
                self.rejected()

    def test_incomplete_or_wrong_typed_receipts_are_rejected(self):
        original = copy.deepcopy(self.receipt)
        for receipt in ([], {}, {k: v for k, v in original.items() if k != "perl"},
                        dict(original, schema=True), dict(original, files=[]), dict(original, files={})):
            with self.subTest(receipt=receipt):
                self.receipt = receipt
                self.save_receipt()
                self.rejected()

    def test_changed_source_pin_or_perl_abi_is_rejected(self):
        original = copy.deepcopy(self.receipt)
        for field in ("runtime", "packages", "perl"):
            with self.subTest(field=field):
                self.receipt = copy.deepcopy(original)
                if field == "runtime":
                    self.receipt[field]["sha256"] = "0" * 64
                elif field == "packages":
                    self.receipt[field][0]["sha256"] = "0" * 64
                else:
                    self.receipt[field]["ABI"] += ";changed"
                self.save_receipt()
                self.rejected()

    def test_changed_native_parser_or_unrecorded_file_is_rejected(self):
        native = next(name for name in self.receipt["files"] if name.endswith("/Expat.so"))
        (self.prefix / native).chmod(0o644)
        (self.prefix / native).write_bytes(b"not the compiled parser")
        self.rejected()
        shutil.copy2(PREFIX / native, self.prefix / native)
        (self.prefix / "unrecorded.pm").write_text("1;")
        self.rejected()

    def test_removed_and_ambiguous_modules_are_rejected_even_with_edited_receipt(self):
        original = copy.deepcopy(self.receipt)
        native = next(name for name in original["files"] if name.endswith("/Expat.so"))
        del self.receipt["files"][native]
        self.save_receipt()
        self.rejected()
        self.receipt = original
        other = "lib/perl5/other/auto/XML/Parser/Expat/Expat.so"
        (self.prefix / other).parent.mkdir(parents=True)
        shutil.copy2(self.prefix / native, self.prefix / other)
        self.receipt["files"][other] = SETUP.digest(self.prefix / other)
        self.save_receipt()
        self.rejected()

    def test_symlink_receipt_and_module_and_nonregular_entries_are_rejected(self):
        receipt = self.prefix / "receipt.json"
        data = receipt.read_bytes()
        receipt.unlink()
        target = self.root / "receipt"
        target.write_bytes(data)
        receipt.symlink_to(target)
        self.rejected()
        receipt.unlink()
        receipt.write_bytes(data)
        (self.prefix / "foreign.pm").symlink_to(target)
        self.rejected()
        (self.prefix / "foreign.pm").unlink()
        os.mkfifo(self.prefix / "pipe")
        self.rejected()

    def test_wrong_archive_checksum_fails_before_extraction_or_build(self):
        destination = self.root / "new/cache"
        with mock.patch.object(SETUP.urllib.request, "urlopen", return_value=io.BytesIO(b"unreviewed")), \
                mock.patch.object(SETUP.tarfile, "open", side_effect=AssertionError("extract")), \
                mock.patch.object(SETUP.subprocess, "run", side_effect=AssertionError("build")):
            with self.assertRaisesRegex(ValueError, "checksum mismatch"):
                SETUP.install(destination)
        self.assertFalse(destination.exists())

    def test_symlinked_destination_parents_fail_before_provisioning(self):
        outside = self.root / "outside"
        outside.mkdir()
        link = self.root / "linked-tools"
        link.symlink_to(outside, target_is_directory=True)
        with mock.patch.object(SETUP.urllib.request, "urlopen", side_effect=AssertionError("network")):
            with self.assertRaisesRegex(ValueError, "symlink"):
                SETUP.install(link / "host-perl" / SETUP.CACHE_NAME)
        self.assertFalse(list(outside.iterdir()))

    def package(self, member):
        stream = io.BytesIO()
        with tarfile.open(fileobj=stream, mode="w:gz") as archive:
            info = tarfile.TarInfo(member)
            info.size = 2
            archive.addfile(info, io.BytesIO(b"1;"))
        data = stream.getvalue()
        return data, [{"name": "fixture", "author": "T/TE/TEST", "sha256": hashlib.sha256(data).hexdigest()}]

    def test_archive_root_and_traversal_fail_before_any_build(self):
        for member in ("wrong/Makefile.PL", "fixture/../../escape"):
            with self.subTest(member=member):
                data, packages = self.package(member)
                destination = self.root / ("outside" if member.startswith("wrong") else "traversal")
                destination.mkdir()
                with mock.patch.object(SETUP.urllib.request, "urlopen", return_value=io.BytesIO(data)), \
                        mock.patch.object(SETUP.subprocess, "run", side_effect=AssertionError("build")):
                    with self.assertRaises((ValueError, tarfile.TarError)):
                        SETUP.prepare_source(packages[0], destination)
                self.assertFalse((self.root / "escape").exists())

    def test_failed_upstream_test_never_installs_or_publishes_cache(self):
        data, packages = self.package("fixture/Makefile.PL")
        commands = []
        def run(command, **_kwargs):
            commands.append(command)
            return subprocess.CompletedProcess(command, int(command == ["make", "test_harness"]))
        with mock.patch.object(SETUP, "RUNTIME", packages[0]), \
                mock.patch.object(SETUP.urllib.request, "urlopen", return_value=io.BytesIO(data)), \
                mock.patch.object(SETUP.subprocess, "run", side_effect=run):
            with self.assertRaisesRegex(ValueError, "build/test failed"):
                SETUP.install(self.root / "unpublished/cache")
        self.assertEqual(commands[-1], ["make", "test_harness"])
        self.assertNotIn(["make", "install"], commands)
        self.assertFalse((self.root / "unpublished/cache").exists())

    def test_failed_module_test_stops_before_module_install(self):
        commands = []
        def run(command, **_kwargs):
            commands.append(command)
            return subprocess.CompletedProcess(command, int(command == ["make", "test"]))
        with mock.patch.object(SETUP.subprocess, "run", side_effect=run):
            with self.assertRaisesRegex(ValueError, "build/test failed"):
                SETUP.run_commands(SETUP.PACKAGES[-1], [["make", "-j2"], ["make", "test"], ["make", "install"]],
                                   self.root, self.env)
        self.assertEqual(commands, [["make", "-j2"], ["make", "test"]])

    def test_corrupt_private_interpreter_rejects_without_executing_it(self):
        marker = self.root / "UNTRUSTED_INTERPRETER_RAN"
        executable = self.prefix / "bin/perl"
        executable.chmod(0o755)
        executable.write_text('#!/bin/sh\ntouch "' + str(marker) + '"\n')
        self.rejected()
        self.assertFalse(marker.exists())

    def test_wrapper_preserves_arguments_and_standard_input(self):
        args = ["space and ünicode", "", 'literal $()`&;"', "--not-an-option"]
        program = 'use JSON::PP; utf8::decode($_) for @ARGV; local $/; print encode_json({args=>\\@ARGV,stdin=><STDIN>,version=>$XML::Parser::VERSION,perl=>"$^V"});'
        result = subprocess.run([str(WRAPPER), "-MXML::Parser", "-e", program, "--", *args],
                                input="literal input\n", env=self.env, capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), {"args": args, "stdin": "literal input\n", "version": "2.59", "perl": "v5.44.0"})

    def test_wrapper_ignores_inherited_perl_code_and_library_options(self):
        poison = self.root / "poison"
        poison.mkdir()
        (poison / "Evil.pm").write_text('die "inherited options executed";')
        env = dict(self.env, PERL5OPT="-MEvil", PERL5LIB=str(poison), PERL_MM_OPT="bad", PERL_MB_OPT="bad", PERL_LOCAL_LIB_ROOT=str(poison), PERL_UNICODE="SDA", PERLIO="bad")
        result = subprocess.run([str(WRAPPER), "-MXML::Parser", "-e", 'print $XML::Parser::VERSION'],
                                env=env, capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "2.59")

    def test_wrapper_missing_cache_fails_before_requested_mutation(self):
        marker = self.root / "MUTATED"
        env = dict(self.env, TOOLS_DIR=str(self.root / "missing"))
        result = subprocess.run([str(WRAPPER), "-e", 'open my $f, ">", $ARGV[0] or die $!; print $f "bad";', str(marker)],
                                env=env, capture_output=True, text=True, timeout=15)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Run: python3", result.stderr)
        self.assertFalse(marker.exists())
        self.assertFalse((self.root / "missing").exists())

    def test_consumers_fail_before_mutation_even_when_conditionally_sourced(self):
        firmware = self.root / "firmware"
        for variant in ("SM-S942B_INS", "SM-G998B_AUT"):
            (firmware / variant / "system/system/etc/permissions").mkdir(parents=True)
        (firmware / "SM-G998B_AUT/system/system/etc/permissions/com.sec.feature.spen_usp.xml").touch()
        program = r'''
mutation() { echo "MUTATED:$*" >> "$MARKER"; return 0; }
GET_PROP() { if [ "$1" = system ]; then echo donor; else echo target; fi; }
GET_FLOATING_FEATURE_CONFIG() { echo true; }
for f in SET_PROP SET_FLOATING_FEATURE_CONFIG SMALI_PATCH DECODE_APK APPLY_PATCH APPLY_SMALI_PATCHES ADD_TO_WORK_DIR DELETE_FROM_WORK_DIR SET_METADATA EVAL; do
    eval "$f() { mutation \"\$@\"; }"
done
LOG() { :; }; LOG_STEP_IN() { :; }; LOG_STEP_OUT() { :; }; LOGW() { :; }; ABORT() { mutation abort; }
if source "$1"; then exit 42; fi
'''
        for consumer in BODIES:
            with self.subTest(consumer=consumer):
                marker = self.root / "mutations"
                env = dict(self.env, TOOLS_DIR=str(self.root / "absent"), MARKER=str(marker),
                           SRC_DIR=str(ROOT), FW_DIR=str(firmware), SOURCE_FIRMWARE="SM-S942B/INS/1",
                           TARGET_FIRMWARE="SM-G998B/AUT/1", SOURCE_PLATFORM_SDK_VERSION="37", TARGET_CODENAME="p3s")
                result = subprocess.run(["bash", "--noprofile", "--norc", "-c", program, "test", str(ROOT / consumer)],
                                        env=env, capture_output=True, text=True, timeout=15)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("XML parser setup:", result.stderr)
                self.assertFalse(marker.exists(), result.stdout + result.stderr)

    def test_bluetooth_private_tool_switch_keeps_the_original_verified_parser(self):
        source = (ROOT / "unica/patches/bluetooth/customize.sh").read_text().split("# Keep helper functions", 1)[0]
        program = source + '\nTOOLS_DIR="$1/private-tools"; BLUETOOTH_TOOLS="$2"; BLUETOOTH_RUNTIME unsupported\n'
        file = self.root / "unica/patches/bluetooth/customize.sh"
        file.parent.mkdir(parents=True)
        file.write_text(program)
        (self.root / "scripts").symlink_to(ROOT / "scripts", target_is_directory=True)
        result = subprocess.run(["bash", str(file), str(self.root), str(self.tools)],
                                env=self.env, capture_output=True, text=True, timeout=15)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("XML parser setup:", result.stderr)
        self.assertIn("Expected state, payload or vaultkeeper action", result.stderr)

    def test_original_embedded_perl_algorithms_are_unchanged(self):
        for consumer, expected in BODIES.items():
            with self.subTest(consumer=consumer):
                bodies = re.findall(r"<<'PERL'\n(.*?)\nPERL(?:\n|$)", (ROOT / consumer).read_text(), re.S)
                self.assertEqual([hashlib.sha256(body.encode()).hexdigest() for body in bodies], expected)

    def test_repeated_xml_callback_trees_are_warning_free(self):
        source = (ROOT / "unica/mods/settings/customize.sh").read_text()
        helper = source.split("<<'PERL'\n", 1)[1].split("\nsub node_raw", 1)[0]
        # Exercise the actual callbacks and repeated tree destruction without
        # firmware. This is not a substitute for the separately retained replay
        # of the large, exact Settings resource inputs.
        program = helper + r'''
my $data = '<resources>' . join('', map {
    qq{<string name="resource_$_">literal &amp; text &#x20ac; $_</string>}
} 1..6000) . '</resources>';
for (1..24) {my $doc=xml($data,0); die unless @{$doc->{root}{children}}==6000;}
print 'ok';
'''
        for seed in range(4):
            with self.subTest(seed=seed):
                result = subprocess.run([str(WRAPPER), "-"], input=program,
                                        env=dict(self.env, PERL_HASH_SEED=str(seed)),
                                        capture_output=True, text=True, timeout=45)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, "ok")
                self.assertFalse(result.stderr)

    def fixture(self):
        decoded, overlay = self.root / "decoded", self.root / "overlay"
        for root in (decoded, overlay):
            (root / "res/values").mkdir(parents=True)
            (root / "res/xml").mkdir()
        (decoded / "AndroidManifest.xml").write_text('<manifest xmlns:android="http://schemas.android.com/apk/res/android"><application/></manifest>')
        (decoded / "res/values/strings.xml").write_text('<resources><!-- unowned bytes --><string name="retained">keep</string></resources>')
        (decoded / "res/xml/sec_top_level_settings.xml").write_text('<PreferenceScreen xmlns:android="http://schemas.android.com/apk/res/android"><Preference android:key="TopLevelAdvancedFeatures"/><Preference android:key="sec_ic_settings_user_manual"/></PreferenceScreen>')
        (overlay / "AndroidManifest.xml").write_text('/application>/i\n<activity android:name="unica.Example"/>')
        (overlay / "res/xml/sec_top_level_settings.xml").write_text('/TopLevelAdvancedFeatures/a\n<Preference android:key="unica"/>')
        (overlay / "res/values/strings.xml").write_text('<resources><string name="unica">literal `id` $(false) ü &amp; text</string></resources>')
        return decoded, overlay

    def inject(self, decoded, overlay):
        return subprocess.run(["bash", str(ROOT / "unica/mods/settings/customize.sh"), "--inject", str(decoded), str(overlay)],
                              env=self.env, capture_output=True, text=True, timeout=15)

    def test_literal_xml_directives_compact_roots_and_repeat_are_preserved(self):
        decoded, overlay = self.fixture()
        first = self.inject(decoded, overlay)
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertFalse(first.stderr)
        before = snapshot(decoded)
        second = self.inject(decoded, overlay)
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(snapshot(decoded), before)
        text = (decoded / "res/values/strings.xml").read_text()
        self.assertIn('<!-- unowned bytes -->', text)
        self.assertIn('literal `id` $(false) ü &amp; text', text)

    def test_doctype_external_entities_and_invalid_namespaces_fail_before_writes(self):
        decoded, overlay = self.fixture()
        before = snapshot(decoded)
        for data in ('<!DOCTYPE x [<!ENTITY steal SYSTEM "file:///must-not-read">]><x>&steal;</x>',
                     '<x android:unknown="unbound"/>', '<x><unclosed></x>'):
            with self.subTest(data=data):
                (overlay / "res/xml/invalid.xml").write_text(data)
                result = self.inject(decoded, overlay)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(snapshot(decoded), before)

    def test_ambiguous_anchor_fails_before_any_planned_settings_write(self):
        decoded, overlay = self.fixture()
        home = decoded / "res/xml/sec_top_level_settings.xml"
        home.write_text(home.read_text().replace('</PreferenceScreen>', '<Preference android:key="duplicate_TopLevelAdvancedFeatures"/></PreferenceScreen>'))
        before = snapshot(decoded)
        result = self.inject(decoded, overlay)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Expected one Settings anchor", result.stderr)
        self.assertEqual(snapshot(decoded), before)


if __name__ == "__main__":
    unittest.main()
