class StellarCore < Formula
  desc "Backbone of the Stellar (XLM) network"
  homepage "https://www.stellar.org/"
  url "https://github.com/stellar/stellar-core.git",
      tag:      "v28.0.0",
      revision: "a9b8613218e141ddb89d621e5f04d4c75a149d36"
  license "Apache-2.0"
  head "https://github.com/stellar/stellar-core.git", branch: "master"

  # Upstream creates releases that use a stable tag (e.g., `v1.2.3`) but are
  # labeled as "pre-release" on GitHub before the version is released, so it's
  # necessary to use the `GithubLatest` strategy.
  livecheck do
    url :stable
    strategy :github_latest
  end

  bottle do
    sha256 cellar: :any, arm64_tahoe:   "807bb65b02eecf983a1e70348ac2e02ff8574872a31eeb81d92f41f6b5e10c92"
    sha256 cellar: :any, arm64_sequoia: "2702f1b6c5ceddf98cc6d3226e3badb38a361054d386c6c7e544ce9a311d25de"
    sha256 cellar: :any, arm64_sonoma:  "85536e4618df4123571639541567f3ad0116aff015c966a0fb2f7794410438ac"
    sha256 cellar: :any, sonoma:        "346c20d53c2f0a1415bcc8bf8661621f8eceb78e976291c050386472ea64e0cb"
    sha256               arm64_linux:   "4297600bfb048bbd102bffe41c1fa41992f34b892f63fd27d91fc517f5c29c52"
    sha256               x86_64_linux:  "ad2d0493abe173d0f99da5636240934937a3bb221d1a590a4f96094783950db5"
  end

  depends_on "autoconf" => :build
  depends_on "automake" => :build
  depends_on "bison" => :build # Bison 3.0.4+
  depends_on "libtool" => :build
  depends_on "pandoc" => :build
  depends_on "pkgconf" => :build
  depends_on "rust" => :build
  depends_on "libpq"

  uses_from_macos "flex" => :build

  on_sonoma :or_older do
    depends_on "coreutils" => :build # for sha256sum
  end

  # https://github.com/stellar/stellar-core/blob/master/INSTALL.md#build-dependencies
  fails_with :gcc do
    version "7"
    cause "Requires C++17 filesystem"
  end

  def install
    # remove toolchain selection
    inreplace "src/Makefile.am", "cargo +$(RUST_TOOLCHAIN_CHANNEL)", "cargo"

    # GCC 13+ no longer transitively includes <cstdint>, which the vendored
    # `libmedida` sources rely on for `uint64_t`. Force-include it.
    # https://github.com/stellar/medida/pull/34
    ENV.append "CXXFLAGS", "-include cstdint" if OS.linux?

    system "./autogen.sh"
    system "./configure", "--disable-silent-rules",
                          "--enable-postgres",
                          *std_configure_args

    # A vendored soroban lockfile pins `ethnum` 1.5.0, which fails to build on
    # current Rust: it transmutes `()` into the now-non-zero-sized
    # `TryFromIntError` (rustc E0512). Pre-extract the crate into the shared
    # `CARGO_HOME` and size-match the transmute so the later build reuses it.
    # https://github.com/nlordell/ethnum-rs/issues/60
    cargo_home = ENV.fetch("CARGO_HOME", "#{Dir.home}/.cargo")
    (buildpath/"ethnum-shim/src").mkpath
    (buildpath/"ethnum-shim/Cargo.toml").write <<~TOML
      [workspace]
      [package]
      name = "ethnum-shim"
      version = "0.0.0"
      edition = "2021"
      [dependencies]
      ethnum = "=1.5.0"
    TOML
    (buildpath/"ethnum-shim/src/main.rs").write "fn main() {}\n"
    system "cargo", "fetch", "--manifest-path", buildpath/"ethnum-shim/Cargo.toml"
    Dir.glob("#{cargo_home}/registry/src/*/ethnum-1.5.0/src/error.rs").each do |error_rs|
      inreplace error_rs, "unsafe { mem::transmute(()) }", "unsafe { mem::transmute(0u8) }"
    end

    system "make", "install"
  end

  test do
    test_categories = %w[
      accountsubentriescount
    ]
    system bin/"stellar-core", "test", test_categories.map { |category| "[#{category}]" }.join(",")
  end
end
