# ci/

`ios-device.yml` 是要放到 `.github/workflows/` 里的构建工作流草稿。

放这里的原因：当前 GitHub token 没有 `workflow` scope，无法直接写 `.github/workflows/`。

启用方式（30 秒）：在 GitHub 网页打开 `ci/ios-device.yml` → 点铅笔 Edit →
把文件名那一栏改成 `.github/workflows/ios-device.yml` → Commit changes。
提交后 Actions 页会出现「iOS device build」，手动 Run 即可产出 `ios-device-unsigned-ipa`。
