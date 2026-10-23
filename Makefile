.PHONY: all build app install uninstall clean

all: app

build:
	swift build -c release --build-system native

app:
	bash scripts/build_app.sh

install: app
	bash scripts/install.sh

uninstall:
	bash scripts/uninstall.sh

clean:
	rm -rf .build build
