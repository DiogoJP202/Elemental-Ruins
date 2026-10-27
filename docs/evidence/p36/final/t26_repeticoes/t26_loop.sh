#!/bin/bash
# Repete o T26 isolado em headless; relatórios no scratchpad (não toca nas evidências).
cd "C:/Users/dsoares/Documents/Projetos/game/.claude/worktrees/charming-mendel-4b469a"
G="C:/Users/dsoares/Tools/Godot/4.7.2-voxel1.7/godot.windows.editor.x86_64.exe"
S="$1"; N="$2"
for i in $(seq 1 $N); do
  timeout 400 "$G" --headless --path . res://scenes/main.tscn -- --p36-selftest --evidence-stage=final --only=T26 --report="$S/t26_$i.json" > "$S/t26_$i.log" 2>&1
  r=$(grep -oE "T26 (PASS|FAIL)" "$S/t26_$i.log" | head -1)
  shift_m=$(grep -oE '"maior_deslocamento_m":[0-9.eE-]+' "$S/t26_$i.log" | head -1)
  echo "run $i: $r $shift_m"
done
