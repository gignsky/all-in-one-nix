{
  description = "Flake packaging for the allin1 CLI";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        python = pkgs.python311;
        py = pkgs.python311Packages;

        julius = py.buildPythonPackage rec {
          pname = "julius";
          version = "0.2.8";
          pyproject = true;

          src = pkgs.fetchPypi {
            inherit pname version;
            hash = "sha256-1pkeZSAAkwq/6kbImMJulf7IRghyga49GndX6skCU9U=";
          };

          build-system = with py; [ hatchling ];
          propagatedBuildInputs = with py; [ torch ];

          pythonImportsCheck = [ "julius" ];
          doCheck = false;
        };

        openunmix = py.buildPythonPackage rec {
          pname = "openunmix";
          version = "1.3.0";
          pyproject = true;

          src = pkgs.fetchPypi {
            inherit pname version;
            hash = "sha256-zJJFznKHA/XQtyxn8BvkFid35hfNxH+bA1ljr6wYD8g=";
          };

          build-system = with py; [ setuptools ];
          propagatedBuildInputs = with py; [
            numpy
            torch
            torchaudio
            tqdm
          ];

          pythonImportsCheck = [ "openunmix" ];
          doCheck = false;
        };

        madmom = py.buildPythonPackage rec {
          pname = "madmom";
          version = "0.16.1";
          format = "setuptools";

          src = pkgs.fetchPypi {
            inherit pname version;
            hash = "sha256-ZKhqKRBufE4MX07JaAHC0ahJLbcQ5P4n4JfaVRfWjLI=";
          };

          nativeBuildInputs = with py; [
            cython
            numpy
            pytest-runner
            setuptools
          ];
          propagatedBuildInputs = with py; [
            mido
            numpy
            scipy
          ];

          pythonImportsCheck = [ "madmom" ];
          doCheck = false;
        };

        natten = py.buildPythonPackage rec {
          pname = "natten";
          version = "0.14.6";
          format = "setuptools";

          src = pkgs.fetchPypi {
            inherit pname version;
            hash = "sha256-cEfs4IGZLFaxiiPO93f/Gb8CGelxH9KzQo9F7A9eHx4=";
          };

          nativeBuildInputs =
            with pkgs;
            [
              ninja
            ]
            ++ (with py; [
              packaging
              setuptools
              torch
              wheel
            ]);
          propagatedBuildInputs = with py; [
            packaging
            torch
          ];

          postPatch = ''
            substituteInPlace setup.py \
              --replace-fail "packages=['natten/']," "packages=find_packages(where='src'),"
          '';

          env.FORCE_CUDA = "0";

          pythonImportsCheck = [ "natten" ];
          doCheck = false;
        };

        demucs = py.buildPythonPackage rec {
          pname = "demucs";
          version = "4.0.1";
          format = "setuptools";

          src = pkgs.fetchPypi {
            inherit pname version;
            hash = "sha256-5FpaeLqueXZ8N7v26pquA4Yt3MoFVQ+3m5JjRqF31xM=";
          };

          nativeBuildInputs = with py; [ setuptools ];
          propagatedBuildInputs = with py; [
            einops
            julius
            numpy
            omegaconf
            openunmix
            pyyaml
            torch
            torchaudio
            tqdm
          ];

          postPatch = ''
            python - <<'PY'
            from pathlib import Path

            def patch_file(path, replacements):
              file_path = Path(path)
              text = file_path.read_text()
              for old, new in replacements:
                if old not in text:
                  raise SystemExit(f"missing expected text in {path}: {old!r}")
                text = text.replace(old, new)
              file_path.write_text(text)

            patch_file(
              "demucs/audio.py",
              [
                (
                  "import lameenc\n",
                  "try:\n    import lameenc\nexcept ImportError:\n    lameenc = None\n",
                ),
                (
                  "    encoder = lameenc.Encoder()\n",
                  "    if lameenc is None:\n        raise RuntimeError('MP3 output requires lameenc, which is not packaged in this flake.')\n    encoder = lameenc.Encoder()\n",
                ),
              ],
            )
            patch_file(
              "demucs/separate.py",
              [
                (
                  "from dora.log import fatal\n",
                  "def fatal(message):\n    raise SystemExit(message)\n",
                ),
              ],
            )
            patch_file(
              "demucs/pretrained.py",
              [
                (
                  "from dora.log import fatal, bold\n",
                  "def fatal(message):\n    raise RuntimeError(message)\n\n\ndef bold(message):\n    return message\n",
                ),
              ],
            )
            patch_file(
              "demucs/states.py",
              [
                (
                  "from dora.log import fatal\n",
                  "def fatal(message):\n    raise RuntimeError(message)\n",
                ),
              ],
            )
            PY
          '';

          pythonImportsCheck = [ "demucs.separate" ];
          doCheck = false;
        };

        allin1Python = python.withPackages (_: [
          py.numpy
          py.librosa
          py."hydra-core"
          py.omegaconf
          py."huggingface-hub"
          py.matplotlib
          py.pandas
          py.scipy
          py."scikit-learn"
          py.tqdm
          py.torch
          py.torchaudio
          demucs
          madmom
          natten
        ]);

        allin1Cli = pkgs.writeShellApplication {
          name = "allin1";
          runtimeInputs = [
            allin1Python
            pkgs.ffmpeg
          ];
          text = ''
            export PYTHONPATH=${self}/src''${PYTHONPATH:+:$PYTHONPATH}
            exec python -m allin1.cli "$@"
          '';
        };

        devCli = pkgs.writeShellScriptBin "allin1" ''
          exec python -m allin1.cli "$@"
        '';
      in
      {
        packages.default = allin1Cli;
        packages.allin1 = allin1Cli;
        packages.pythonEnv = allin1Python;

        apps.default = {
          type = "app";
          program = "${allin1Cli}/bin/allin1";
        };

        devShells.default = pkgs.mkShell {
          packages = [
            allin1Python
            devCli
            pkgs.ffmpeg
          ];

          shellHook = ''
            export PYTHONPATH="$PWD/src''${PYTHONPATH:+:$PYTHONPATH}"
          '';
        };
      }
    );
}
