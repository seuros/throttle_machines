# frozen_string_literal: true

require "mkmf"

def create_noop_makefile(message)
  warn message
  warn "ThrottleMachines will fall back to pure Ruby backend."
  File.write("Makefile", <<~MAKEFILE)
    .PHONY: all install clean

    all:
    \t@echo "#{message}"

    install:
    \t@echo "No native extension to install"

    clean:
    \t@echo "Nothing to clean"
  MAKEFILE
  exit 0
end

create_noop_makefile("Skipping native extension on #{RUBY_ENGINE}") unless RUBY_ENGINE == "ruby"

unless system("cargo --version > /dev/null 2>&1")
  create_noop_makefile("Skipping native extension (Cargo not found)")
end

begin
  require "pathname"
  require "rb_sys/mkmf"

  create_rust_makefile("throttle_machines_native/throttle_machines_native") do |r|
    ffi_dir = Pathname(__dir__)
    r.ext_dir = begin
      ffi_dir.relative_path_from(Pathname(Dir.pwd)).to_s
    rescue ArgumentError
      ffi_dir.expand_path.to_s
    end
    r.profile = ENV.fetch("RB_SYS_CARGO_PROFILE", :release).to_sym
  end

  makefile_path = File.join(Dir.pwd, "Makefile")
  if File.exist?(makefile_path)
    manifest_path = File.expand_path(__dir__)
    contents = File.read(makefile_path)
    contents.gsub!(/^RB_SYS_CARGO_MANIFEST_DIR \?=.*$/, "RB_SYS_CARGO_MANIFEST_DIR ?= #{manifest_path}")
    File.write(makefile_path, contents)
  end
rescue LoadError => e
  create_noop_makefile("Skipping native extension (rb_sys gem not available: #{e.message})")
rescue StandardError => e
  create_noop_makefile("Skipping native extension (compilation setup failed: #{e.message})")
end
