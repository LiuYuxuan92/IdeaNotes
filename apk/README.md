IdeaNotes APK downloads

- Source commit: `a2113f3` on `master`
- App version: `1.0.3+4`
- Build target: Android release APKs (split by ABI)
- Primary file for most phones: `IdeaNotes-1.0.3-a2113f3-arm64-v8a.apk`
- 32-bit fallback: `IdeaNotes-1.0.3-a2113f3-armeabi-v7a.apk`
- SHA-256: see matching `.sha256` files

This build includes:
- AI OCR correction before preview and save, so text like `今天吃了3牛肉` can be corrected before structuring
- AI preview now shows both original OCR text and corrected text
- Chinese diet notes keep their health meaning while also carrying the `记录` label
- Note detail shows multi-tag classification more clearly on mobile

Note:
- GitHub does not accept the universal APK because it exceeds the 100 MB file limit, so this branch publishes split APKs instead.
