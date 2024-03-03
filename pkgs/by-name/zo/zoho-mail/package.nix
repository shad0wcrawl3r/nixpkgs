{ lib, stdenv, appimageTools, fetchurl, pkgs }:
let
pname = "zoho-mail";
version = "1.6.1";
inherit (stdenv.hostPlatform) system;
throwSystem = throw "Unsupported system: ${system}";
suffix = {
x86_64-linux = "linux_x86_64.AppImage";
}.${system} or throwSystem;
src = fetchurl {
url = "https://downloads.zohocdn.com/zmail-desktop/linux/zoho-mail-desktop-lite-x64-v${version}.AppImage";
hash = {
x86_64-linux = "sha256-dXl46ELcuQS4e9geNPUV0hB+LKOru9q5oCc8ar3/9Mo=";
}.${system} or throwSystem;
};
appimageContents = appimageTools.extractType2 {
inherit pname version src;
};
meta = with lib; {
description = "Zoho Mail Desktop";
homepage = "https://zoho.com/mail/desktop";
license = licenses.unfree;
maintainers = [ "shad0wcrawl3r" ];
platforms = [ "x86_64-linux" ];
};
in
appimageTools.wrapType2 rec {
inherit pname version src meta; # no 32bit needed
extraPkgs = pkgs: with pkgs; [ xorg.libxkbfile alsa-lib dbus-glib gtk3 nss gnused libdbusmenu-gtk3 ];
extraInstallCommands = ''
mv $out/bin/{${pname}-${version},${pname}}
install -Dm444 ${appimageContents}/zoho-mail-desktop.desktop -t $out/share/applications
install -Dm444 ${appimageContents}/zoho-mail-desktop.png -t $out/share/pixmaps
substituteInPlace $out/share/applications/zoho-mail-desktop.desktop \
--replace-fail 'Exec=AppRun --no-sandbox %U' 'Exec=${pname}'
'';
}
