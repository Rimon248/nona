# Android Xray library

`apps/client/android/app/libs/libXray.aar` is the unmodified Android artifact from the official [libXray v26.10.31 release](https://github.com/XTLS/libXray/releases/tag/v26.10.31). Its SHA-256 is `4c90532f61ff8363e7fcf52e064ff1aa66d065e06afbadc0ea4c6acf384c452f`. The downloaded `libxray-android.zip` release asset had SHA-256 `fb99f04acf379cc2957c1e1d0ce2b3c0005d3f49974a44c09a11242a0562c1ca`, matching the release metadata. The archive contains the AAR and a generated sources JAR; the AAR contains Android binaries for four ABIs.

The wrapper source is [libXray v26.10.31](https://github.com/XTLS/libXray/tree/v26.10.31). Its embedded core is [Xray-core v26.10.31](https://github.com/XTLS/Xray-core/tree/v26.10.31). License texts are in `licenses/` and are copied into the Android APK assets. libXray is MIT licensed; Xray-core is MPL-2.0 licensed. No app code was copied from v2rayN or v2rayNG.

The iOS build downloads the official `libxray-apple-cgo.zip` asset from the same release at build time and verifies SHA-256 `2666babc1a91d8570a49bc817487338e7a71f17618e02a601e861928d254b95a`. The extracted XCFramework is ignored by Git; the repository retains the source and license attribution.

The AAR is used only by Android. Other platform builds do not link it. The Hysteria 2 core is not yet bundled. Before release, verify source availability, attribution, ABI sizes, Android foreground-service declarations, and all transitive license obligations against the final build.
