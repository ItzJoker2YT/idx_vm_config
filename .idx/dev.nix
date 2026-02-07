{ pkgs, ... }: {
  # Use the stable channel for reliability
  channel = "stable-24.05";

  # SYSTEM PACKAGES
  packages = with pkgs; [
    # --- VM & System Tools (CRITICAL) ---
    qemu             # Provides qemu-system-x86_64 and qemu-img
    cloud-utils      # Provides cloud-localds (Required for cloud-init)
    cdrkit           # Utilities for ISO manipulation
    
    # --- Essential Utilities (Fixes script crashes) ---
    openssl          # Fixes "openssl: command not found"
    netcat-openbsd   # Fixes "nc: command not found" (Zombie Killer)
    procps           # Fixes "pgrep/pkill" (Process detection)
    util-linux       # Fixes "fallocate/lscpu"
    
    # --- Network & Connectivity ---
    wget
    curl
    git
    nano
    openssh
    sshpass          # Fixes "Auto-Login"

    # --- Docker ---
    docker

    # --- Python Environment ---
    python3
    python3Packages.pip
    python3Packages.virtualenv
  ];

  # Environment Variables
  env = {
    EDITOR = "nano";
  };

  # IDX Configuration
  idx = {
    extensions = [
      "ms-python.python"
      "rangav.vscode-thunder-client" 
    ];
    
    workspace = {
      # Runs when the workspace is created (First time only)
      onCreate = {
        install-python-deps = ''
          python3 -m venv venv
          source venv/bin/activate
          pip install discord.py docker paramiko
        '';
      };
      
      # Runs EVERY TIME the workspace starts (The Fix)
      onStart = {
        # Unlock ALL storage pools (Disk, Overlay, RAM)
        fix-permissions = ''
          # 1. Persistent Disk
          sudo mkdir -p /mnt/vms_storage
          sudo chown -R $USER:$USER /mnt/vms_storage
          chmod 755 /mnt/vms_storage
          
          # 2. Overlay Storage
          sudo mkdir -p /nix/vms_storage
          sudo chown -R $USER:$USER /nix/vms_storage
          
          # 3. RAM Disks
          sudo mkdir -p /var/vms_storage /run/vms_storage
          sudo chown -R $USER:$USER /var/vms_storage /run/vms_storage
          
          echo "✅ All storage pools unlocked."
        '';
        
        activate-venv = "source venv/bin/activate";
      };
    };
  };
}