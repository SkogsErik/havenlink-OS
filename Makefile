# HavenLink OS Makefile

.PHONY: help image clean test

help:
	@echo "HavenLink OS Build System"
	@echo ""
	@echo "Targets:"
	@echo "  image       - Build the OS image"
	@echo "  clean       - Clean build artifacts"
	@echo "  test        - Run tests"
	@echo ""
	@echo "Options:"
	@echo "  ARCH=       - Architecture: aarch64, x86_64 (default: aarch64)"
	@echo "  OUTPUT=     - Output directory (default: .)"

image:
	@echo "Building HavenLink OS image..."
	@chmod +x scripts/build-image.sh
	@scripts/build-image.sh -a $(or $(ARCH),aarch64) -o $(or $(OUTPUT),.)

clean:
	@echo "Cleaning build artifacts..."
	@rm -rf /tmp/havenlink-build
	@rm -f *.img *.img.gz

test:
	@echo "Running tests..."
	@# Would run pytest here
	@echo "No tests configured yet"
