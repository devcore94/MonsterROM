"""Host-only regression checks; all firmware mutation helpers are replaced."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
BOOLEAN_OPTIONS = (
    "UN1CA_QPR2_CAMERA_METADATA",
    "UN1CA_QPR2_CAMERA_PATH",
    "UN1CA_QPR2_SUBJECT_CPU_PREVIEW",
    "UN1CA_QPR2_CPU_LEAVES",
    "UN1CA_QPR2_MAINLINE",
    "UN1CA_QPR2_SWCODEC",
)
RUNTIME_OPTION = "UN1CA_QPR2_RUNTIME_COHORT"
FINITE_CONTRACTS = (
    ("qpr2/mainline/modules.sha256", "UN1CA_QPR2_MAINLINE", "true"),
    ("qpr2/runtime_cohort/components.sha256", RUNTIME_OPTION, "trial-r15"),
    ("qpr2/cpu_leaves/libraries.sha256", "UN1CA_QPR2_CPU_LEAVES", "true"),
)


class ParadigmProfileTests(unittest.TestCase):
    def run_profile(self, options, sdk=37, existing_codename=True, manifests=None,
                    checked_source=False):
        # Run the real root up to its first QPR2 component. This includes any
        # writes that incorrectly precede validation, but never runs firmware
        # tools: all mutation helpers, checksum calls and cd are test doubles.
        source = (ROOT / "unica/mods/paradigm/customize.sh").read_text()
        prefix = source[:source.index("    # QPR2 mainline\n")] + "fi\n"
        harness = r'''
set -e
record() { printf '%s\n' "$*" >> "$TRACE_FILE"; }
GET_PROP() { [ "$EXISTING_CODENAME" = true ] && printf 'Paradigm\n' || :; }
LOG() { :; }
LOG_STEP_IN() { :; }
LOG_STEP_OUT() { :; }
ABORT() { printf '%s\n' "$*" >&2; return 1; }
EVAL() { record "EVAL $*"; }
SET_PROP() { record "SET_PROP $*"; }
DELETE_FROM_WORK_DIR() { record "DELETE_FROM_WORK_DIR $*"; }
ADD_TO_WORK_DIR() { record "ADD_TO_WORK_DIR $*"; }
SET_METADATA() { record "SET_METADATA $*"; }
APPLY_PATCH() { record "APPLY_PATCH $*"; }
sha256sum() { [ "$1" = -c ] || command sha256sum "$@"; }
cd() { :; }
if [ "$CHECKED_SOURCE" = true ]; then
    if source "$PROFILE_FRAGMENT"; then :; else exit "$?"; fi
else
    source "$PROFILE_FRAGMENT"
fi
for option in UN1CA_QPR2_CAMERA_METADATA UN1CA_QPR2_CAMERA_PATH UN1CA_QPR2_SUBJECT_CPU_PREVIEW UN1CA_QPR2_CPU_LEAVES UN1CA_QPR2_MAINLINE UN1CA_QPR2_SWCODEC UN1CA_QPR2_RUNTIME_COHORT; do
    printf '%s=%s\n' "$option" "${!option-unset}"
done
'''
        with tempfile.TemporaryDirectory(prefix="paradigm-profile-") as tmp:
            folder = Path(tmp)
            fragment = folder / "profile.sh"
            trace = folder / "mutations.log"
            fragment.write_text(prefix)
            module = folder / "module"
            for relative, _, _ in FINITE_CONTRACTS:
                contents = (ROOT / "unica/mods/paradigm" / relative).read_text()
                contents = (manifests or {}).get(relative, contents)
                if contents is not None:
                    path = module / relative
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_text(contents)
            env = {k: v for k, v in os.environ.items()
                   if k not in (*BOOLEAN_OPTIONS, RUNTIME_OPTION)
                   and k not in ("BASH_ENV", "ENV", "SHELLOPTS", "BASHOPTS")}
            env.update({
                "SRC_DIR": str(ROOT),
                "MODPATH": str(module),
                "SOURCE_PLATFORM_SDK_VERSION": str(sdk),
                "TARGET_AUDIO_SUPPORT_ACH_RINGTONE": "true",
                "EXISTING_CODENAME": str(existing_codename).lower(),
                "CHECKED_SOURCE": str(checked_source).lower(),
                "TRACE_FILE": str(trace),
                "PROFILE_FRAGMENT": str(fragment),
                **options,
            })
            result = subprocess.run(["bash", "--noprofile", "--norc", "-c", harness],
                                    env=env, capture_output=True, text=True, timeout=10)
            mutations = trace.read_text().splitlines() if trace.exists() else []
        return result, mutations

    def test_invalid_booleans_reject_before_any_mutation(self):
        for name in BOOLEAN_OPTIONS:
            for value in ("TRUE", "yes", "1", "false "):
                with self.subTest(option=name, value=value):
                    result, mutations = self.run_profile({name: value}, existing_codename=False)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn(name, result.stderr)
                    self.assertEqual(mutations, [])

    def test_invalid_runtime_rejects_before_any_mutation(self):
        result, mutations = self.run_profile({RUNTIME_OPTION: "trial-r51"}, existing_codename=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(RUNTIME_OPTION, result.stderr)
        self.assertEqual(mutations, [])

    def test_partial_camera_profile_rejects_before_any_mutation(self):
        for metadata, path in (("true", "false"), ("false", "true")):
            with self.subTest(metadata=metadata, path=path):
                result, mutations = self.run_profile({
                    "UN1CA_QPR2_CAMERA_METADATA": metadata,
                    "UN1CA_QPR2_CAMERA_PATH": path,
                }, existing_codename=False)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("metadata and Path", result.stderr)
                self.assertEqual(mutations, [])

    def test_default_profile_is_unchanged(self):
        result, mutations = self.run_profile({})
        self.assertEqual(result.returncode, 0, result.stderr)
        values = dict(line.split("=", 1) for line in result.stdout.splitlines())
        self.assertEqual(values, {
            "UN1CA_QPR2_CAMERA_METADATA": "true",
            "UN1CA_QPR2_CAMERA_PATH": "true",
            "UN1CA_QPR2_SUBJECT_CPU_PREVIEW": "true",
            "UN1CA_QPR2_CPU_LEAVES": "true",
            "UN1CA_QPR2_MAINLINE": "true",
            "UN1CA_QPR2_SWCODEC": "false",
            RUNTIME_OPTION: "off",
        })
        self.assertEqual([line.split()[0] for line in mutations],
                         ["SET_PROP"] * 6 + ["APPLY_PATCH"]
                         + ["ADD_TO_WORK_DIR"] * 3 + ["SET_METADATA"] * 3
                         + ["APPLY_PATCH"] * 2)

    def test_explicit_valid_profiles_are_preserved(self):
        for runtime in ("off", "trial-r15"):
            options = {key: "false" for key in BOOLEAN_OPTIONS}
            options[RUNTIME_OPTION] = runtime
            result, _ = self.run_profile(options)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(dict(line.split("=", 1) for line in result.stdout.splitlines()), options)

    def test_older_layout_does_not_validate_or_default_options(self):
        result, mutations = self.run_profile({RUNTIME_OPTION: "unrelated"}, sdk=36)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(mutations, [])
        values = dict(line.split("=", 1) for line in result.stdout.splitlines())
        self.assertEqual(values[RUNTIME_OPTION], "unrelated")
        self.assertTrue(all(values[name] == "unset" for name in BOOLEAN_OPTIONS))

    def test_enabled_components_reject_incomplete_or_duplicate_contracts(self):
        for relative, option, value in FINITE_CONTRACTS:
            original = (ROOT / "unica/mods/paradigm" / relative).read_text()
            first = original.splitlines(keepends=True)[0]
            variants = {
                "missing": None,
                "empty": "",
                "truncated": first,
                "duplicated": original + first,
                "altered": original.replace(original.split()[1], "unreviewed", 1),
            }
            for case, contents in variants.items():
                with self.subTest(contract=relative, case=case):
                    result, mutations = self.run_profile(
                        {option: value}, existing_codename=False,
                        manifests={relative: contents})
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn(relative, result.stderr)
                    self.assertEqual(mutations, [])

    def test_disabled_components_do_not_require_their_contracts(self):
        options = {"UN1CA_QPR2_MAINLINE": "false", "UN1CA_QPR2_CPU_LEAVES": "false",
                   RUNTIME_OPTION: "off"}
        result, _ = self.run_profile(options, manifests={p: None for p, _, _ in FINITE_CONTRACTS})
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_checked_source_cannot_suppress_rejection(self):
        cases = (
            ({"UN1CA_QPR2_MAINLINE": "yes"}, None),
            ({"UN1CA_QPR2_CAMERA_PATH": "false"}, None),
            ({}, {"qpr2/mainline/modules.sha256": ""}),
        )
        for options, manifests in cases:
            with self.subTest(options=options, manifests=manifests):
                result, mutations = self.run_profile(
                    options, existing_codename=False, manifests=manifests,
                    checked_source=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(mutations, [])


if __name__ == "__main__":
    unittest.main()
