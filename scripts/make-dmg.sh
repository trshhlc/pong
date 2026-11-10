#!/bin/sh
# Собирает DMG для релиза: приложение, ярлык на «Программы» и оформленное окно с фоном.
# Использование: scripts/make-dmg.sh путь/к/pong.app
# Раскладку окна (размер, фон, места иконок) выставляет Finder, поэтому при первом
# запуске macOS спросит, можно ли терминалу управлять Finder, — нужно разрешить.
set -eu

APP="${1:?Укажи путь к .app}"
APP="${APP%/}"   # без слеша в конце, иначе путь склеится неправильно
NAME="$(basename "$APP" .app)"   # pong — для имени файла образа
PLIST="$APP/Contents/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
# Красивое имя (@pong 🪽): так будут называться приложение в образе и сам образ
DISPLAY="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$PLIST" 2>/dev/null || echo "$NAME")"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/$NAME-$VERSION.dmg"
BG="$ROOT/assets/dmg-background@2x.png"   # 1200×800, обычную 600×400 делаем из него

# Те же числа, что в шаблоне installer-kit: окно 600×400, иконки 128, центры иконок
WIN_W=600; WIN_H=400
TITLE_H=32   # высота заголовка окна в macOS 26: размер окна в Finder считается вместе с ним
ICON_SIZE=128; ICON_Y=190
APP_X=150; APPS_X=450

WORK="$(mktemp -d)"
MOUNT=""
cleanup() {
    [ -n "$MOUNT" ] && hdiutil detach "$MOUNT" -force -quiet 2>/dev/null
    rm -rf "$WORK"
}
trap cleanup EXIT

STAGE="$WORK/stage"
mkdir -p "$STAGE/.background"
ditto "$APP" "$STAGE/$DISPLAY.app"
ln -s /Applications "$STAGE/Applications"

# Фон: обычная и Retina-версия в одном TIFF, Finder сам берёт нужную
sips -z "$WIN_H" "$WIN_W" "$BG" --out "$WORK/bg.png" >/dev/null
tiffutil -cathidpicheck "$WORK/bg.png" "$BG" -out "$STAGE/.background/background.tiff" 2>/dev/null

# Сначала образ с записью: Finder сохранит в него раскладку окна (файл .DS_Store).
# APFS, потому что на HFS+ имя тома с эмодзи превращается в «untitled»
hdiutil create -volname "$DISPLAY" -srcfolder "$STAGE" -fs APFS -format UDRW -ov "$WORK/rw.dmg" >/dev/null
MOUNT="$(hdiutil attach "$WORK/rw.dmg" -readwrite -noverify -noautoopen | awk -F '\t' '/\/Volumes\// { print $NF }')"

osascript - "$MOUNT" "$DISPLAY.app" <<EOF >/dev/null
on run argv
    set dmg to (POSIX file (item 1 of argv)) as alias
    set appName to item 2 of argv
    tell application "Finder"
        open dmg
        set win to container window of dmg
        set current view of win to icon view
        set toolbar visible of win to false
        set statusbar visible of win to false
        set pathbar visible of win to false
        set bounds of win to {200, 120, 200 + $WIN_W, 120 + $WIN_H + $TITLE_H}
        set opts to icon view options of win
        set arrangement of opts to not arranged
        set icon size of opts to $ICON_SIZE
        set background picture of opts to file ".background:background.tiff" of dmg
        set extension hidden of item appName of dmg to true   -- подпись без «.app»
        set position of item appName of dmg to {$APP_X, $ICON_Y}
        set position of item "Applications" of dmg to {$APPS_X, $ICON_Y}
        close win
        open dmg
        update dmg without registering applications
        delay 1
        close container window of dmg
    end tell
end run
EOF

# Ждём, пока Finder допишет раскладку на диск
i=0
while [ ! -f "$MOUNT/.DS_Store" ] && [ "$i" -lt 20 ]; do sleep 0.5; i=$((i + 1)); done
[ -f "$MOUNT/.DS_Store" ] || { echo "Finder не сохранил раскладку окна" >&2; exit 1; }

sync
hdiutil detach "$MOUNT" -quiet
MOUNT=""

# Итоговый сжатый образ только для чтения
mkdir -p "$ROOT/build"
hdiutil convert "$WORK/rw.dmg" -format UDZO -imagekey zlib-level=9 -ov -o "$OUT" >/dev/null

echo "Готово: $OUT"
