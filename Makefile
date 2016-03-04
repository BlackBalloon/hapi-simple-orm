init:
	npm install

clean:
	rm -rf lib/

build:
	coffee -o lib/ -c src/

dist:
	clean build
