.PHONY: all build app dmg install uninstall clean

all: app dmg

build:
	swift build -c release --build-system native

app:
	bash scripts/build_app.sh

dmg: app
	bash scripts/create_dmg.sh

install: app
	bash scripts/install.sh

uninstall:
	bash scripts/uninstall.sh

clean:
	rm -rf .build build
