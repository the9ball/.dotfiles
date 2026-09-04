# rigorous-review コスト最適化・後続メモ

これはGit管理下の引き継ぎ用メモであり、実装計画の正本ではない。詳細な手法・対象runtime・依存関係・予算・受入条件は、各Phaseの着手時点で改めて検討する。

## 現状（2026-09-05）

Phase A（測定契約・synthetic fixture）は observe-only で完了し、`2342b5e` に固定済み。Phase B〜Dは未適用で、現状はlegacy strict flowを使用する。

Phase Bを再開するには、全dispatch経路を覆う保証付きruntime境界、または全role dispatchを単一harnessへ限定する設計判断が必要。

## 将来のPhase

- Phase A（測定）: 実行コストと出力の測定契約を維持し、比較可能なfixture・実測値を整える。
- Phase B（preflight／epoch）: role開始前の現物検証とdispatch境界を確立し、ownerとfail-closed条件を確認する。
- Phase C（packet／JCS）: packet schema、内容・path境界、JCS方式を、その時点で検証可能な実装に合わせて定める。
- Phase D（budget／delta）: 予算checkpointと差分台帳を設計し、停止・再開・承認履歴を保持する。
- Phase E（比較／go-no-go）: legacyと候補方式を別engagementで比較し、品質・証拠被覆・コストを確認してから既定化を判断する。
