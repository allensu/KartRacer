# KartRacer

一款原創的 3D 卡丁車賽車遊戲，用 Godot 4 製作，在瀏覽器裡就能玩。
目標：吃道具、攻擊對手、單人與最多 4 人線上對戰，每場 8 名車手。

## 目前進度：第 1 步

- 一台可以開的卡丁車：加速、煞車／倒車、轉彎、甩尾
- 甩尾集氣：藍色火花放開得到小加速，橘色火花得到大加速
- 一條原創測試賽道「Sunset Loop」：路肩、草地緩衝區（會減速）、護欄、起終點拱門
- 3 圈計時賽：倒數起跑、圈數、單圈時間、終點成績

所有 3D 模型目前都由程式產生（沒有外部素材），之後在「質感打磨」階段換成正式美術。

## 操作

| 動作 | 鍵盤 | 手把 |
| --- | --- | --- |
| 油門 | W / ↑ | A / RT |
| 煞車、倒車 | S / ↓ | X / LT |
| 轉向 | A D / ← → | 左搖桿 |
| 甩尾（轉彎時按住） | Space / Shift | LB / RB |
| 重新開始 | R | Back |

## 開發

需要 [Godot 4.3](https://godotengine.org/download/archive/4.3-stable/)（標準版即可）。用 Godot 開啟這個資料夾，按 F5 執行。

- `scripts/main.gd`：場景組裝、倒數、圈數、成績
- `scripts/kart.gd`：卡丁車物理與外觀（之後 AI 和線上玩家共用同一套物理）
- `scripts/track.gd`：由曲線產生賽道、碰撞與場景
- `scripts/chase_camera.gd`、`scripts/hud.gd`：鏡頭與畫面資訊
- `tests/autodrive_test.gd`：自動駕駛跑完 3 圈的冒煙測試

```
godot --headless --fixed-fps 60 -s res://tests/autodrive_test.gd
```

## 網頁版

每次推送都會由 GitHub Actions 匯出網頁版（`.github/workflows/web.yml`），
可在該次執行的 Artifacts 下載 `kartracer-web`。若 repo 開啟了 GitHub Pages
（Settings → Pages → Source 選 GitHub Actions），`main` 分支會自動部署成可直接遊玩的網址。

自行架站時直接放上 `build/web` 的檔案即可；本專案使用單執行緒匯出，不需要特殊的 COOP/COEP 標頭。
