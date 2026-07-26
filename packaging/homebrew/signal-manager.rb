# Homebrew formula cho Signal Manager.
# File này nằm ở repo tap: <bạn>/homebrew-signal-manager, đường dẫn Formula/signal-manager.rb
# Sau mỗi release: cập nhật `url` (tag mới) và `sha256` (xem docs/phat-hanh-homebrew.md).
class SignalManager < Formula
  desc "Run multiple Signal Desktop accounts on one Mac, with a local dashboard"
  homepage "https://github.com/dev-lo-18tuoi/multi-signal"
  url "https://github.com/dev-lo-18tuoi/multi-signal/archive/refs/tags/v2.4.0.tar.gz"
  sha256 "13e2391ada84281dc1c4c80777542c0d4cbc6ba659215f1387b966482077eebc"
  license "MIT"

  depends_on :macos

  def install
    libexec.install "signal-manager.sh", "signal_manager_server.py", "signal-manager-ui.html"
    chmod 0755, libexec/"signal-manager.sh"
    # wrapper exec giữ nguyên $0 = đường dẫn thật trong libexec,
    # để engine tìm thấy server + UI nằm cạnh nó
    (bin/"signal-manager").write_exec_script libexec/"signal-manager.sh"
  end

  def caveats
    <<~EOS
      Cần cài sẵn Signal Desktop: https://signal.org/download

      Tạo app quản lý (chạy một lần):
        signal-manager install

      Sau đó mở "Signal Manager" trong ~/Applications.
      Mỗi account Signal cần một số điện thoại riêng đã đăng ký trên điện thoại.
    EOS
  end

  test do
    assert_match "signal-manager", shell_output("#{bin}/signal-manager help")
  end
end
