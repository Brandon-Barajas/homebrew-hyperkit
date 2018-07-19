class Hyperkit < Formula
  desc "Lightweight virtualization hypervisor for macOS"
  homepage "https://github.com/moby/hyperkit"
  url "https://github.com/moby/hyperkit/archive/v0.20180403.tar.gz"
  sha256 "e2739b034f20d9437696de48ace42600f55b7213292ec255032b2ef55f508297"
  head "https://github.com/moby/hyperkit.git"

  resource "tinycorelinux" do
    url "https://dl.bintray.com/markeissler/homebrew/hyperkit-kernel/tinycorelinux_8.x.tar.gz"
    sha256 "560c1d2d3a0f12f9b1200eec57ca5c1d107cf4823d3880e09505fcd9cd39141a"
  end

  def install
    system "make"

    bin.install "build/hyperkit"
    man1.install "hyperkit.1"
  end

  test do
    # simple test when not in a vm that supports guests (i.e. VT-x disabled)
    unless Hardware::CPU.features.include? :vmx
      return system bin/"hyperkit", "-version"
    end

    # download tinycorelinux kernel and initrd, boot system, check for prompt
    resource("tinycorelinux").stage do |context|
      tmpdir = context.staging.tmpdir
      path_resource_versioned = Dir.glob(tmpdir.join("tinycorelinux_[0-9]*"))[0]
      cp(File.join(path_resource_versioned, "vmlinuz"), testpath)
      cp(File.join(path_resource_versioned, "initrd.gz"), testpath)
    end

    (testpath/"test_hyperkit.exp").write <<-EOS.undent
      #!/usr/bin/env expect -d

      set KERNEL "./vmlinuz"
      set KERNEL_INITRD "./initrd.gz"
      set KERNEL_CMDLINE "earlyprintk=serial console=ttyS0"

      set MEM {512M}
      set PCI_DEV1 {0:0,hostbridge}
      set PCI_DEV2 {31,lpc}
      set LPC_DEV {com1,stdio}
      set ACPI {-A}

      spawn #{bin}/hyperkit $ACPI -m $MEM -s $PCI_DEV1 -s $PCI_DEV2 -l $LPC_DEV -f kexec,$KERNEL,$KERNEL_INITRD,$KERNEL_CMDLINE
      set pid [exp_pid]
      set timeout 20

      expect {
        timeout { puts "FAIL boot"; exec kill -9 $pid; exit 1 }
        "\\r\\ntc@box:~$ "
      }

      send "sudo halt\\r\\n";

      expect {
        timeout { puts "FAIL shutdown"; exec kill -9 $pid; exit 1 }
        "reboot: System halted"
      }

      expect eof

      puts "\\nPASS"
    EOS
    system "expect", "test_hyperkit.exp"
  end
end
