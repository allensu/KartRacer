# KartRacer

一款原創的 3D 卡丁車賽車遊戲，用 Godot 4 製作，在瀏覽器裡就能玩。
目標：吃道具、攻擊對手、單人與最多 4 人線上對戰，每場 8 名車手。

## 目前進度：第 2 步

- 8 人比賽：你和 7 名 AI 對手（Blaze、Pip、Rocco、Nova、Taro、Mika、Juno），每位有不同的速度、跑線和甩尾習慣
- 即時名次與排名表，落後的 AI 會稍微追趕，讓整場比賽保持緊湊
- 賽道上 3 排道具箱，名次越後面越容易拿到好道具：
  - **NITRO**：立即加速
  - **OIL SLICK**：往後丟一灘油，踩到的人會打轉
  - **SEEKER**：沿著賽道追擊前一名
  - **SHIELD**：護盾 10 秒，可擋下一次攻擊
- 3 圈比賽，終點顯示 8 人成績表；完賽後由電腦接手開完收操圈
- 卡丁車：加速、煞車／倒車、轉彎、甩尾集氣（藍色小加速、橘色大加速）
- 原創測試賽道「Sunset Loop」

所有 3D 模型目前都由程式產生（沒有外部素材），之後在「質感打磨」階段換成正式美術。

## 操作

| 動作 | 鍵盤 | 手把 |
| --- | --- | --- |
| 油門 | W / ↑ | A / RT |
| 煞車、倒車 | S / ↓ | X / LT |
| 轉向 | A D / ← → | 左搖桿 |
| 甩尾（轉彎時按住） | Space / Shift | LB / RB |
| 使用道具 | E / Ctrl / J | B / Y |
| 重新開始 | R | Back |

## 開發

需要 [Godot 4.3](https://godotengine.org/download/archive/4.3-stable/)（標準版即可）。用 Godot 開啟這個資料夾，按 F5 執行。

- `scripts/main.gd`：場景組裝、倒數、圈數、成績
- `scripts/kart.gd`：卡丁車物理、外觀、道具欄與被擊中反應（玩家、AI、之後的線上玩家共用）
- `scripts/ai_driver.gd`：AI 駕駛（跑線、甩尾、使用道具、卡住自救）
- `scripts/items.gd`：道具機率表、道具箱、油漬、追蹤飛彈
- `scripts/track.gd`：由曲線產生賽道、碰撞與場景
- `scripts/chase_camera.gd`、`scripts/hud.gd`：鏡頭與畫面資訊
- `tests/autodrive_test.gd`：8 台車全由 AI 駕駛跑完整場比賽的冒煙測試
- `tests/screenshots.gd`：產生道具與成績畫面的截圖（需要有畫面的環境，例如 `xvfb-run`）

```
godot --headless --fixed-fps 60 -s res://tests/autodrive_test.gd
```

## 網頁版

每次推送都會由 GitHub Actions 匯出網頁版（`.github/workflows/web.yml`），
可在該次執行的 Artifacts 下載 `kartracer-web`。若 repo 開啟了 GitHub Pages
（Settings → Pages → Source 選 GitHub Actions），`main` 分支會自動部署成可直接遊玩的網址。

自行架站時直接放上 `build/web` 的檔案即可；本專案使用單執行緒匯出，不需要特殊的 COOP/COEP 標頭。
