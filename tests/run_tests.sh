#!/usr/bin/env bash
# Runs the headless test suites. Requires Godot 4.3 and GDSiON 0.7 in bin/.
#
#   tests/run_tests.sh            run every suite
#   tests/run_tests.sh --strict   also treat default-on GDScript warnings as errors
#
# The Godot binary is taken from $GODOT (default: godot).

set -u

GODOT="${GODOT:-godot}"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SUITES=(Phase1Tests Phase2Tests Phase3Tests Phase4Tests Phase5Tests Phase6Tests Phase6UiTests Phase6WavTests Phase7Tests ValueSliderTests HelpTests)
STRICT=0
[[ "${1:-}" == "--strict" ]] && STRICT=1

cd "$PROJECT_DIR" || exit 1

if [[ ! -f bin/libgdsion.gdextension ]]; then
	echo "GDSiON is missing: extract libgdsion into bin/ (see README, 'Notes for developers')." >&2
	exit 1
fi

# In strict mode a temporary override.cfg turns warnings into errors; an
# existing override.cfg is restored afterwards.
OVERRIDE_BACKUP=""
cleanup() {
	if [[ $STRICT -eq 1 ]]; then
		rm -f override.cfg
		[[ -n "$OVERRIDE_BACKUP" ]] && mv "$OVERRIDE_BACKUP" override.cfg
	fi
}
trap cleanup EXIT

if [[ $STRICT -eq 1 ]]; then
	if [[ -f override.cfg ]]; then
		OVERRIDE_BACKUP="$(mktemp)"
		mv override.cfg "$OVERRIDE_BACKUP"
	fi
	{
		echo "[debug]"
		echo
		for warning in unassigned_variable unassigned_variable_op_assign unused_variable unused_local_constant \
			unused_private_class_variable unused_parameter unused_signal shadowed_variable shadowed_variable_base_class \
			shadowed_global_identifier unreachable_code unreachable_pattern standalone_expression standalone_ternary \
			incompatible_ternary untyped_declaration narrowing_conversion int_as_enum_without_cast int_as_enum_without_match \
			enum_variable_without_default static_called_on_instance redundant_static_unload redundant_await \
			confusable_identifier confusable_local_declaration confusable_local_usage inference_on_variant \
			native_method_override get_node_default_without_onready onready_with_export deprecated_keyword; do
			echo "gdscript/warnings/$warning=2"
		done
	} > override.cfg
fi

# Import twice: the first pass registers the GDExtension, the second compiles against it.
"$GODOT" --headless --import > /dev/null 2>&1
"$GODOT" --headless --import > /dev/null 2>&1

FAILED=0

run_scene() {
	local name="$1" expected="$2"
	local output
	output="$("$GODOT" --headless --quit-after 20000 "res://tests/$name.tscn" 2>&1)"
	
	if grep -q "SCRIPT ERROR" <<< "$output" || ! grep -q "$expected" <<< "$output"; then
		echo "FAIL  $name"
		grep -E "FAIL|SCRIPT ERROR|TESTS|CHECKED" -A1 <<< "$output" | sed 's/^/      /'
		FAILED=1
	else
		echo "ok    $name ($(grep -E "TESTS|CHECKED|HELP LINES" <<< "$output" | head -1))"
	fi
}

run_scene CheckAll "0 failed"
for suite in "${SUITES[@]}"; do
	if [[ "$suite" == "HelpTests" ]]; then
		run_scene "$suite" "unbound 0"
	else
		run_scene "$suite" "TESTS: 0 failures"
	fi
done

exit $FAILED
