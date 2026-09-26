#!/bin/bash
# run.sh — gera o projeto, builda, instala e abre o AUREA Plantão no simulador, sem abrir o Xcode.
#
#   ./run.sh              build + instala + abre
#   ./run.sh --revisao    abre sem a proteção de captura do prontuário (só DEBUG, para
#                         screenshots de revisão de design — em Release a flag não existe)
set -euo pipefail
cd "$(dirname "$0")"
SIMULADOR="iPhone 17 Pro"
xcodegen generate --quiet
mkdir -p build && touch build/.metadata_never_index
xcrun simctl list devices booted | grep -q "$SIMULADOR" || xcrun simctl boot "$SIMULADOR"
xcodebuild -project AureaPlantao.xcodeproj -scheme AureaPlantao -configuration Debug \
  -destination "platform=iOS Simulator,name=$SIMULADOR" -derivedDataPath build build -quiet
xcrun simctl install "$SIMULADOR" build/Build/Products/Debug-iphonesimulator/AureaPlantao.app
ARGS=(); [[ "${1:-}" == "--revisao" ]] && ARGS+=(-revisaoDeDesign)
xcrun simctl launch "$SIMULADOR" com.zenixcode.aurea.plantao "${ARGS[@]}"
echo "✅ Face ID no simulador: Features ▸ Face ID ▸ Enrolled, depois Matching Face."
