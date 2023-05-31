#!/bin/sh

run() {
	rm -f test-tmp/log
	DYLD_INSERT_LIBRARIES=$PWD/build/trace-nix.so LD_PRELOAD=$PWD/build/trace-nix.so TRACE_NIX=test-tmp/log \
		nix-shell --run : -p -- "$@" # 2>/dev/null
}

run_without_p() {
	rm -f test-tmp/log
	DYLD_INSERT_LIBRARIES=$PWD/build/trace-nix.so LD_PRELOAD=$PWD/build/trace-nix.so TRACE_NIX=test-tmp/log \
		nix-shell --run : -- "$@" 2>/dev/null
}

result=0

dir_b3sum() {
	find "$1" -mindepth 1 -maxdepth 1 -printf '%P=%y\0' |
		sed -z 's/[^dlf]$/u/' |
		LC_ALL=C sort -z |
		b3sum |
		head -c 32
}

check() {
	local name="$1" key="$2" val="$3"

	if ! grep -qzFx -- "$key" test-tmp/log; then
		printf "\33[31mFail: %s: can't find key\33[m\n" "$name"
		return
		result=1
	fi

	local actual_val="$(grep -zFx -A1 -- "$key" test-tmp/log | tail -zn1 | tr -d '\0')"
	if [ "$val" != "$actual_val" ]; then
		printf "\33[31mFail: %s: expected '%s', got '%s'\33[m\n" \
			"$name" "$val" "$actual_val"
		return
		result=1
	fi

	printf "\33[32mOK: %s\33[m\n" "$name"
}

rm -rf test-tmp
mkdir test-tmp
echo '"foo"' > test-tmp/test.nix
: > test-tmp/empty
ln -s empty test-tmp/link

mkdir test-tmp/repo
echo '{ somekey = "somevalue"; }' > test-tmp/repo/default.nix
tar -C test-tmp/repo -cf test-tmp/repo.tar .
x=""
for i in {1..64};do
	x=x$x
	# mkdir -p test-tmp/many-dirs/$x
done

export XDG_CACHE_HOME="$PWD/test-tmp/xdg-cache"
run "fetchTarball file://$PWD/test-tmp/repo.tar?$RANDOM$RANDOM$RANDOM"



exit
run 'with import <unstable> {}; bash'
check import-channel \
	"s/nix/var/nix/profiles/per-user/root/channels/unstable" \
	"l$(readlink /nix/var/nix/profiles/per-user/root/channels/unstable)"

run 'with import <nonexistentChannel> {}; bash'
check import-channel-ne \
	"s/nix/var/nix/profiles/per-user/root/channels/nonexistentChannel" '-'


run 'import ./test-tmp/test.nix'
check import-relative-nix \
	"s$PWD/test-tmp/test.nix" "+"

run 'import ./test-tmp'
check import-relative-nix-dir \
	"s$PWD/test-tmp" "d"

run 'import ./nonexistent.nix'
check import-relative-nix-ne \
	"s$PWD/nonexistent.nix" "-"


run 'builtins.readFile ./test-tmp/test.nix'
check builtins.readFile \
	"f$PWD/test-tmp/test.nix" \
	"$(b3sum ./test-tmp/test.nix | head -c 32)"

run 'builtins.readFile "/nonexistent/readFile"'
check builtins.readFile-ne \
	"f/nonexistent/readFile" "-"

run 'builtins.readFile ./test-tmp'
check builtins.readFile-dir \
	"f$PWD/test-tmp" "e"

run 'builtins.readFile ./test-tmp/empty'
check builtins.readFile-empty \
	"f$PWD/test-tmp/empty" \
	"$(b3sum ./test-tmp/empty | head -c 32)"


run 'builtins.readDir ./test-tmp'
check builtins.readDir \
	"d$PWD/test-tmp" "$(dir_b3sum ./test-tmp)"

run 'builtins.readDir "/nonexistent/readDir"'
check builtins.readDir-ne \
	"d/nonexistent/readDir" "-"


run 'builtins.readDir ./test-tmp/many-dirs'
check builtins.readDir-many-dirs \
	"d$PWD/test-tmp/many-dirs" "$(dir_b3sum ./test-tmp/many-dirs)"

run_without_p
check implicit:shell.nix \
	"s$PWD/shell.nix" "-"
check implicit:default.nix \
	"s$PWD/default.nix" "-"

exit $result
