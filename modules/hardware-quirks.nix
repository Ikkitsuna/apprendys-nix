{ config, pkgs, lib, ... }: {
  # Touchpad I2C mort après warm boot (ALPS/Elan, vieux portables) — bug terrain V1.
  # Fix validé Blackview : unbind / sleep 0.3 / bind.
  systemd.services.apprendys-touchpad-rebind = {
    description = "Apprendys — rebind touchpad I2C (vieux PC)";
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      for dev in /sys/bus/i2c/drivers/i2c_hid_acpi/i2c-*; do
        [ -e "$dev" ] || continue
        name=$(basename "$dev")
        echo "$name" > /sys/bus/i2c/drivers/i2c_hid_acpi/unbind 2>/dev/null || true
        sleep 0.3
        echo "$name" > /sys/bus/i2c/drivers/i2c_hid_acpi/bind 2>/dev/null || true
      done
    '';
  };
}
