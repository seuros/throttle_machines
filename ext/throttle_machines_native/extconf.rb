# frozen_string_literal: true

require "mkmf"

def can_compile_native?
  # Check for Cargo
  return false unless system("cargo --version > /dev/null 2>&1")

  # Check for rb_sys gem
  begin
    Gem::Specification.find_by_name("rb_sys")
    true
  rescue Gem::MissingSpecError
    false
  end
end

if can_compile_native?
  require "rb_sys/mkmf"
  create_rust_makefile("throttle_machines_native/throttle_machines_native") do |r|
    r.path = "ffi"
  end
else
  # Create stub Makefile that does nothing - allows gem install to succeed
  # without native extension (falls back to pure Ruby)
  File.write("Makefile", <<~MAKEFILE)
    .PHONY: all install clean

    all:
    \t@echo "Skipping native extension build (Cargo or rb_sys not available)"

    install:
    \t@echo "No native extension to install"

    clean:
    \t@echo "Nothing to clean"
  MAKEFILE
end
