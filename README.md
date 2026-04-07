# Stashing for iOS 9.2 - 10.2.1

Stash 3rd party components to make more space for them!

## Building

The project uses [Theos](https://theos.dev) and builds inside a container so no
local iOS toolchain is required.

### Docker

```sh
# One-step build
docker compose up --build

# Or manually
docker build -t stash-build -f Containerfile .
docker run --rm -v "$PWD:/build:Z" stash-build
```

### Podman

```sh
# One-step build
podman-compose up --build

# Or manually
podman build -t stash-build -f Containerfile .
podman run --rm -v "$PWD:/build:Z" stash-build
```

The `.deb` package is written to `packages/`.

### Local

Install [Theos](https://theos.dev) (includes toolchain and SDK):

```sh
bash -c "$(curl -fsSL https://raw.githubusercontent.com/theos/theos/master/bin/install-theos)"
```

Install the iPhoneOS 10.3 SDK (required by the project):

```sh
$THEOS/bin/install-sdk iPhoneOS10.3
```

Then build:

```sh
make package FINALPACKAGE=1
```
