# KartRacer

一款原創的 3D 卡丁車賽車遊戲，用 Godot 4 製作，在瀏覽器裡就能玩。
目標：吃道具、攻擊對手、單人與最多 4 人線上對戰，每場 8 名車手。

## 目前進度：第 3 步

- **線上多人**：主選單可以單人遊玩、建立房間或輸入 4 個字母的房間代碼加入。最多 4 位玩家，空位由 AI 補滿 8 人，由房主按下開始。

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
| 重新開始（單人） | R | Back |
| 回主選單／離開房間 | Esc | |

## 開發

需要 [Godot 4.3](https://godotengine.org/download/archive/4.3-stable/)（標準版即可）。用 Godot 開啟這個資料夾，按 F5 執行。

- `scripts/main.gd`：場景組裝、倒數、圈數、成績
- `scripts/kart.gd`：卡丁車物理、外觀、道具欄與被擊中反應（玩家、AI、之後的線上玩家共用）
- `scripts/ai_driver.gd`：AI 駕駛（跑線、甩尾、使用道具、卡住自救）
- `scripts/items.gd`：道具機率表、道具箱、油漬、追蹤飛彈
- `scripts/track.gd`：由曲線產生賽道、碰撞與場景
- `scripts/chase_camera.gd`、`scripts/hud.gd`：鏡頭與畫面資訊
- `tests/autodrive_test.gd`：8 台車全由 AI 駕駛跑完整場比賽的冒煙測試
- `tests/net_test.gd`：一台房主加多台玩家透過轉發伺服器實際跑完整場的連線測試
- `scripts/net.gd`、`scripts/menu.gd`：連線狀態、房間大廳與主選單
- `tests/screenshots.gd`：產生道具與成績畫面的截圖（需要有畫面的環境，例如 `xvfb-run`）

```
godot --headless --fixed-fps 60 -s res://tests/autodrive_test.gd
```

## 連線伺服器（線上多人）

`server/` 是一個很小的 Node.js WebSocket 轉發伺服器：只負責房間代碼和轉送訊息，不跑遊戲邏輯。
每台電腦模擬自己的車（房主另外模擬 AI 車），每秒送 20 次狀態給其他人；
道具以事件傳送，被打中與否由被打中那台車的電腦判定。

**部署到 Render（免費方案）**：Render 後台 → New → Blueprint → 選這個 repo → Apply，
會依照 `render.yaml` 建立 `kartracer-relay` 服務。免費方案閒置 15 分鐘會休眠，
第一個人連線時要等大約 1 分鐘喚醒。

遊戲預設連到 `wss://kartracer-relay.onrender.com`（`scripts/net.gd` 的 `DEFAULT_SERVER`）。
如果 Render 給的網址不同，改這個常數，或在遊戲網址後面加上 `?server=wss://你的網址`。

本機測試：

```
cd server && npm install && npm test   # 協定測試
node server.js                         # 預設 8080 埠
KARTRACER_SERVER=ws://localhost:8080 godot   # 開兩個視窗，一個建房、一個加入
```

## 網頁版

每次推送都會由 GitHub Actions 匯出網頁版（`.github/workflows/web.yml`），
可在該次執行的 Artifacts 下載 `kartracer-web`。若 repo 開啟了 GitHub Pages
（Settings → Pages → Source 選 GitHub Actions），`main` 分支會自動部署成可直接遊玩的網址。

自行架站時直接放上 `build/web` 的檔案即可；本專案使用單執行緒匯出，不需要特殊的 COOP/COEP 標頭。
