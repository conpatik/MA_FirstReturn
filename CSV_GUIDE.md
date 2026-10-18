# CSV診断版 v1.2

## 変更点

検知条件・初期値はv1.0と同じです。v1.2では、起動後の確定足再計算がOHLCから矢印を追加したり、未検知のクロスを検知済みにしたりする不具合を修正しました。通常チャートでは従来どおり通知します。

起動時の進行中足の開始時刻を境界として固定します。その時刻より前は履歴推定、その時刻以降はティックで観測したサインのみを表示・保持します。履歴再取得やprev_calculatedのリセットが発生しても、この境界は同じ稼働中は変わりません。未観測の区間や停止中の値動きから後付けのサインは作りません。

同じ足の途中でサインが出た後に、足の確定時に逆クロスが発生した場合、元のサインを保持し、逆方向の新しいクロスは未検知として開始します。

## 保存先（初期設定）

`InpCSVEnabled=true`、`InpCSVCommon=true` が初期設定です。

MT5の **ファイル → 共通データフォルダを開く → Files → MA_FirstReturn** を開いてください。

通常のWindowsパスは次の形式です。

```text
C:\Users\＜ユーザー名＞\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MA_FirstReturn\
```

ファイル名の例：`MA_FirstReturn_v1.2_XAUUSD_PERIOD_H1_＜チャートID＞_＜起動識別子＞.csv`

起動・付け直し・パラメーター変更・新しいテストごとに別ファイルを作成します。実際の絶対パスはMT5のエキスパート／テスターのログに `CSV output:` として表示します。ファイルを開けない場合は初期化エラーにしてログに理由を表示します。

`InpCSVCommon=false` の場合は、通常チャートではそのMT5の `MQL5/Files/MA_FirstReturn`、テスターでは実行エージェント側の `MQL5/Files/MA_FirstReturn` に保存されます。探しやすさのため、まずはtrueを推奨します。CSV検証にはローカルエージェントを使ってください。

## 使い方

1. v1.0をチャートから外し、同梱フォルダを `MQL5/Indicators` にコピーしてv1.2を設置します。
2. テスターのビジュアルモードでXAUUSD・H1、モデル「リアルティックに基づいた全ティック」、確認したい期間を指定します。
3. CSV設定4項目は初期値のtrueのままで実行します。
4. テスト完了後、該当CSVを添付してください。サインの位置が気になる画像もあると、目視の狙いとの比較ができます。

EX5はコンパイル済みです。再コンパイルする場合はMQ5・`FirstReturnCore.mqh`・`FirstReturnCSV.mqh`を同じフォルダに置いてください。DLL許可・自動売買許可は不要です。

## CSV設定

| 設定 | 初期値 | 意味 |
|---|---|---|
| InpCSVEnabled | true | CSVを出力する |
| InpCSVCommon | true | 共通データフォルダに保存する |
| InpCSVHistory | true | 初回計算時の過去足を出力する |
| InpCSVStateChanges | true | 状態変化の行も出力する |

形式はUTF-8・カンマ区切り、先頭行に英語の列名、合計44列です。全ティックの価格は保存しません。確定足の一括記録後・状態変化時・サイン時・終了時に保存内容を反映します。末尾の進行中足は、確定するまでCLOSED_BARとしては出力されません。

## eventとsource

| event | source | 意味 |
|---|---|---|
| HISTORY_BAR | OHLC_APPROX | 装着／テスト開始時点の確定済み履歴。OHLCからの推定 |
| CLOSED_BAR | CLOSED_PREPARATION | 起動後、新たに確定した足の準備条件スナップショット。タッチの新規判定はしない |
| LIVE_SIGNAL | TICK | 観測した現在価格が接近帯に入って実際に発生したサイン |
| STATE_CHANGE | OHLC_APPROX / CLOSED_PREPARATION / TICK | 履歴・確定足・現在価格での状態変化。サイン数には加算しない |

新足ごとの内部再計算では、同じ確定足のスナップショットを重複出力しません。STATE_CHANGEは補助行なので、同じbar_timeに複数行存在します。TICKの状態記録は全ティックを保存せず、状態名が変わったときと新しい足の最初の評価時に出します。

**実際に動作中に検知したサインを数えるときは、event=LIVE_SIGNALだけを抽出してください。** HISTORY_BARのsignal_directionは過去の推定、CLOSED_BARのsignal_directionは保持済みライブ矢印だけです。同じサインを重複集計しないでください。CLOSED_BARにOHLC_TOUCH_APPROXが出ないことがv1.2の確認点です。

## 列の説明

| 列 | 内容 |
|---|---|
| event, source | 記録種別・判定に使用した情報の種類 |
| observed_time, observed_msc | 記録を処理したサーバー時刻・取得可能な最新銘柄ティックのミリ秒時刻（Unix epoch）。HISTORY_BARは当時の検知時刻ではない |
| bar_time | 判定対象の足の開始時刻。MT5チャートと同じサーバー時間で、日本時間への自動変換はしない |
| symbol, timeframe | 銘柄・チャート時間足 |
| state_before, state_after | 同じ評価価格における、処理前・処理後の内部状態の分類 |
| reason | 確定クロス・ブレイク・離れ・期限切れ・推定タッチなど。複数ある場合は縦棒区切り |
| signal_direction, setup_direction | その行のサイン方向・保持しているクロス方向。BUY / SELL / NONE |
| open, high, low, close | 確定足のOHLC。TICK行は記録時点までの進行中足OHLCでcloseが検知価格 |
| fast_ma, slow_ma | 使用した短期・中期SMA |
| atr_used | 傾き・離れ・接近帯に使用したATR。TICK行では直近確定足ATR |
| range_atr | 直前範囲の評価に使った1本前のATR。TICK行は0 |
| fast_delta, slow_delta | 現在のMA－InpSlopeBars本前のMA |
| fast_delta_atr, slow_delta_atr | 上記をatr_usedで割った値。売りは両方が-InpSlopeATR未満、買いは両方が+InpSlopeATR超 |
| trend_ok | MAの並びと両方の傾きがセットアップ方向に一致するか。1 / 0 |
| range_top, range_bottom, range_width_atr, range_valid | 対象足より前の計測本数による候補レンジ。TICK行では空欄。range_validは幅の条件のみ |
| cross_event, breakout_event | その確定足でのクロス・候補範囲外への終値突破。breakout_eventだけではレンジ幅の合格を意味しない。TICK行はNONE |
| active_cross_time, active_break_time | 現在保持しているクロス・レンジブレイクの成立足の時刻。未成立は空欄 |
| active_range_top, active_range_bottom | 保持しているブレイク時点のレンジ境界。候補レンジとは区別する。未成立は0 |
| pair_gap_bars, break_age_bars | クロスと保持ブレイクの本数差・保持ブレイクからの経過本数。未成立は空欄 |
| departed_before, departed_after, consumed | 離れ確認の前後と、そのクロスで検知済みか。1 / 0 |
| touch_lower, touch_upper | 使用した短期SMA接近帯の下端・上端 |
| arrow_price | サインがある場合の矢印の描画価格。検知価格はcloseを参照 |
| parameters | 判定・描画に使用した設定値の組。縦棒区切り |

## stateと主なreason

| state | 意味 |
|---|---|
| WAIT_CROSS | 確定クロス待ち |
| WAIT_BREAKOUT | 同じ方向のブレイク待ち、または保持ブレイクの期限切れ |
| DIRECTION_MISMATCH | クロスと保持ブレイクの方向が不一致 |
| PAIR_TOO_FAR | クロスと保持ブレイクが10本など指定間隔を超えている |
| WAIT_NEXT_BAR | 両条件の成立足。次足以降まで待つ |
| WAIT_SLOPE | MAの並び／両MAの傾きが条件を満たさない |
| WAIT_DEPARTURE | 確定終値が短期MAから十分に離れるのを待つ |
| WAIT_RETURN | 準備完了。短期MAへの最初の接近待ち |
| DETECTED | そのクロスで検知済み |

期限切れの確定足はreasonに `EXPIRED` が入り、その後はWAIT_BREAKOUT等に移ります。`FIRST_RETURN_TOUCH` はライブ検知、`OHLC_TOUCH_APPROX` は過去足からの推定、`LIVE_SIGNAL_RETAINED` は保持済み矢印の確定足記録です。

## 検証範囲

コンパイル（0 errors / 0 warnings）、共通判定コア20シナリオ、CSVヘッダーと書込み44列の対応を確認済みです。いただいたv1.1のCSVの6,488確定足と記録済み実検知9件を判定コアに順次入力し、問題の2026/08/17 18:00買い・2026/09/22 05:00売りでは後付け矢印も検知済み状態も発生しないことを確認しました。時刻はサーバー時間です。

この確認はCSVからの状態再構築で、全ティックの再テストではありません。修正で待機が継続するため、再テストでは元の9件に加えて後続の新しい実検知が発生する可能性があり、件数が9件に一致することは合格条件ではありません。MT5テスターのティック再実行・チャート表示・通知の実送信は未検証です。テスターではPopup・サウンド・Pushを送らず、CSVと矢印で確認します。

再起動等でライブ検知メモリは失われ、過去足から再計算する制約はv1.0と同じです。CSVは各稼働中に観測した記録として保持されます。

