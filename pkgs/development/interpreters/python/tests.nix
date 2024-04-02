# Tests for the Python interpreters, package sets and environments.
#
# Each Python interpreter has a `passthru.tests` which is the attribute set
# returned by this function. For example, for Python 3 the tests are run with
#
# $ nix-build -A python3.tests
#
{ stdenv
, python
, runCommand
, lib
, callPackage
, pkgs
}:

let
  # Test whether the interpreter behaves in the different types of environments
  # we aim to support.
  environmentTests = let
    envs = let
      inherit python;
      pythonEnv = python.withPackages(ps: with ps; [ ]);
      pythonVirtualEnv = if python.isPy3k
        then
           python.withPackages(ps: with ps; [ virtualenv ])
        else
          python.buildEnv.override {
            extraLibs = with python.pkgs; [ virtualenv ];
            # Collisions because of namespaces __init__.py
            ignoreCollisions = true;
          };
    in {
      # Plain Python interpreter
      plain = rec {
        env = python;
        interpreter = env.interpreter;
        is_venv = "False";
        is_nixenv = "False";
        is_virtualenv = "False";
      };
    } // lib.optionalAttrs (!python.isPyPy) {
      # Use virtualenv with symlinks from a Nix env.
      nixenv-virtualenv-links = rec {
        env = runCommand "${python.name}-virtualenv-links" {} ''
          ${pythonVirtualEnv.interpreter} -m virtualenv --system-site-packages --symlinks --no-seed $out
        '';
        interpreter = "${env}/bin/${python.executable}";
        is_venv = "False";
        is_nixenv = "True";
        is_virtualenv = "True";
      };
    } // lib.optionalAttrs (!python.isPyPy) {
      # Use virtualenv with copies from a Nix env.
      nixenv-virtualenv-copies = rec {
        env = runCommand "${python.name}-virtualenv-copies" {} ''
          ${pythonVirtualEnv.interpreter} -m virtualenv --system-site-packages --copies --no-seed $out
        '';
        interpreter = "${env}/bin/${python.executable}";
        is_venv = "False";
        is_nixenv = "True";
        is_virtualenv = "True";
      };
    } // lib.optionalAttrs (python.implementation != "graal") {
      # Python Nix environment (python.buildEnv)
      nixenv = rec {
        env = pythonEnv;
        interpreter = env.interpreter;
        is_venv = "False";
        is_nixenv = "True";
        is_virtualenv = "False";
      };
    } // lib.optionalAttrs (python.pythonAtLeast "3.8" && (!python.isPyPy)) {
      # Venv built using links to plain Python
      # Python 2 does not support venv
      # TODO: PyPy executable name is incorrect, it should be pypy-c or pypy-3c instead of pypy and pypy3.
      plain-venv-links = rec {
        env = runCommand "${python.name}-venv-links" {} ''
          ${python.interpreter} -m venv --system-site-packages --symlinks --without-pip $out
        '';
        interpreter = "${env}/bin/${python.executable}";
        is_venv = "True";
        is_nixenv = "False";
        is_virtualenv = "False";
      };
    } // lib.optionalAttrs (python.pythonAtLeast "3.8" && (!python.isPyPy)) {
      # Venv built using copies from plain Python
      # Python 2 does not support venv
      # TODO: PyPy executable name is incorrect, it should be pypy-c or pypy-3c instead of pypy and pypy3.
      plain-venv-copies = rec {
        env = runCommand "${python.name}-venv-copies" {} ''
          ${python.interpreter} -m venv --system-site-packages --copies --without-pip $out
        '';
        interpreter = "${env}/bin/${python.executable}";
        is_venv = "True";
        is_nixenv = "False";
        is_virtualenv = "False";
      };
    } // lib.optionalAttrs (python.pythonAtLeast "3.8") {
      # Venv built using Python Nix environment (python.buildEnv)
      nixenv-venv-links = rec {
        env = runCommand "${python.name}-venv-links" {} ''
          ${pythonEnv.interpreter} -m venv --system-site-packages --symlinks --without-pip $out
        '';
        interpreter = "${env}/bin/${pythonEnv.executable}";
        is_venv = "True";
        is_nixenv = "True";
        is_virtualenv = "False";
      };
    } // lib.optionalAttrs (python.pythonAtLeast "3.8") {
      # Venv built using Python Nix environment (python.buildEnv)
      nixenv-venv-copies = rec {
        env = runCommand "${python.name}-venv-copies" {} ''
          ${pythonEnv.interpreter} -m venv --system-site-packages --copies --without-pip $out
        '';
        interpreter = "${env}/bin/${pythonEnv.executable}";
        is_venv = "True";
        is_nixenv = "True";
        is_virtualenv = "False";
      };
    };

    testfun = name: attrs: runCommand "${python.name}-tests-${name}" ({
      inherit (python) pythonVersion;
    } // attrs) ''
      mkdir $out

      # set up the test files
      cp -r ${./tests/test_environments} tests
      chmod -R +w tests
      substituteAllInPlace tests/test_python.py

      # run the tests by invoking the interpreter via full path
      echo "absolute path: ${attrs.interpreter}"
      ${attrs.interpreter} -m unittest discover --verbose tests 2>&1 | tee "$out/full.txt"

      # run the tests by invoking the interpreter via $PATH
      export PATH="$(dirname ${attrs.interpreter}):$PATH"
      echo "PATH: $(basename ${attrs.interpreter})"
      "$(basename ${attrs.interpreter})" -m unittest discover --verbose tests 2>&1 | tee "$out/path.txt"

      # make sure we get the right path when invoking through a result link
      ln -s "${attrs.env}" result
      relative="result/bin/$(basename ${attrs.interpreter})"
      expected="$PWD/$relative"
      actual="$(./$relative -c "import sys; print(sys.executable)" | tee "$out/result.txt")"
      if [ "$actual" != "$expected" ]; then
        echo "expected $expected, got $actual"
        exit 1
      fi

      # if we got this far, the tests passed
      touch $out/success
    '';

  in lib.mapAttrs testfun envs;

  # Integration tests involving the package set.
  # All PyPy package builds are broken at the moment
  integrationTests = lib.optionalAttrs (!python.isPyPy) (
    lib.optionalAttrs (python.isPy3k && !stdenv.isDarwin) { # darwin has no split-debug
      cpython-gdb = callPackage ./tests/test_cpython_gdb {
        interpreter = python;
      };
    } // lib.optionalAttrs (python.pythonAtLeast "3.7") {
      # Before the addition of NIX_PYTHONPREFIX mypy was broken with typed packages
      nix-pythonprefix-mypy = callPackage ./tests/test_nix_pythonprefix {
        interpreter = python;
      };
      # Make sure tkinter is importable. See https://github.com/NixOS/nixpkgs/issues/238990
      tkinter = callPackage ./tests/test_tkinter {
        interpreter = python;
      };
    }
  );

  # Tests to ensure overriding works as expected.
  overrideTests = let
    extension = self: super: {
      foobar = super.numpy;
    };
    # `pythonInterpreters.pypy39_prebuilt` does not expose an attribute
    # name (is not present in top-level `pkgs`).
    is_prebuilt = python: python.pythonAttr == null;
  in lib.optionalAttrs (python.isPy3k) ({
    test-packageOverrides = let
      myPython = let
        self = python.override {
          packageOverrides = extension;
          inherit self;
        };
      in self;
    in assert myPython.pkgs.foobar == myPython.pkgs.numpy; myPython.withPackages(ps: with ps; [ foobar ]);
    # overrideScope is broken currently
    # test-overrideScope = let
    #  myPackages = python.pkgs.overrideScope extension;
    # in assert myPackages.foobar == myPackages.numpy; myPackages.python.withPackages(ps: with ps; [ foobar ]);
    #
    # Have to skip prebuilt python as it's not present in top-level
    # `pkgs` as an attribute.
  } // lib.optionalAttrs (python ? pythonAttr && !is_prebuilt python) {
    # Test applying overrides using pythonPackagesOverlays.
    test-pythonPackagesExtensions = let
      pkgs_ = pkgs.extend(final: prev: {
        pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
          (python-final: python-prev: {
            foo = python-prev.setuptools;
          })
        ];
      });
    in pkgs_.${python.pythonAttr}.pkgs.foo;
  });

  condaTests = let
    requests = callPackage ({
        autoPatchelfHook,
        fetchurl,
        pythonCondaPackages,
      }:
      python.pkgs.buildPythonPackage {
        pname = "requests";
        version = "2.24.0";
        format = "other";
        src = fetchurl {
          url = "https://repo.anaconda.com/pkgs/main/noarch/requests-2.24.0-py_0.tar.bz2";
          sha256 = "02qzaf6gwsqbcs69pix1fnjxzgnngwzvrsy65h1d521g750mjvvp";
        };
        nativeBuildInputs = [ autoPatchelfHook ] ++ (with python.pkgs; [
          condaUnpackHook condaInstallHook
        ]);
        buildInputs = [
          pythonCondaPackages.condaPatchelfLibs
        ];
        propagatedBuildInputs = with python.pkgs; [
          chardet idna urllib3 certifi
        ];
      }
    ) {};
    pythonWithRequests = requests.pythonModule.withPackages (ps: [ requests ]);
    in lib.optionalAttrs (python.isPy3k && stdenv.isLinux)
    {
      condaExamplePackage = runCommand "import-requests" {} ''
        ${pythonWithRequests.interpreter} -c "import requests" > $out
      '';
    };

in lib.optionalAttrs (stdenv.hostPlatform == stdenv.buildPlatform ) (environmentTests // integrationTests // overrideTests // condaTests)
