# x-ghostty ワークスペース

[x-ghostty](x-ghostty/) を [Ideal-Driven Development(IDD)](https://github.com/banr1/ideal-driven-development) で周回するワークスペースです。2026-09-30 に Atlas Builder から移行しました。

## 構造

```text
<workspace>/
└── x-ghostty/          # プロジェクト。idd はここで実行する
    ├── IDEAL.md        # 人間所有の正本(実現したい状態)。周回は読むだけで書き換えない
    └── .idd/           # progress.md(条件台帳)/ knowledge.md / cycles/ / journal.jsonl(台帳)
```

フレームワーク本体はこのリポジトリの外にあります(`idd` は `~/.local/bin/idd`)。プロジェクト側に置かれるのは `IDEAL.md` と `.idd/` だけです。

## 使い方

```bash
cd x-ghostty
idd status                 # 状態・停止理由・次の一手
idd show                   # 最新の周回記録(人間への問いもここ)
idd loop                   # 周回を回す(既定 25 回まで)
idd resume --note "…"      # 人間の確認・回答を台帳に刻み、停止状態を解除する
idd refine                 # 変更意図から始める尋問で IDEAL.md を書き直す
idd watch                  # 走行中のループを別の端末から観る
```

周回が `ask` / `blocked` / `realized` で止まったら人間の手番です。`idd status` が次の一手を示します。

## 履歴

`git log -- x-ghostty` に `atlas-builder: …`(2026-08-07〜09-07、35 周回)と `idd: …` の commit が並びます。Atlas Builder の制御プレーン(`.atlas-builder/`)とプロジェクト側の旧状態(`x-ghostty/.atlas-builder/state/`、`x-ghostty/ESSENCE.md`)は、移行の commit より前の履歴から取り出せます。
