# MonsterROM_NEXT

MonsterROM_NEXT brings the Galaxy S26+ One UI 9.5 beta to the Exynos Galaxy S21+ using UN1CA's partition and patch layout. The first target is the international **SM-G996B** (`t2s`).

| Input | Device | Build |
| --- | --- | --- |
| One UI 9.5 system, system_ext and product | Galaxy S26+ SM-S947B, EUX (`m2s`) | `S947BXXS6BZK1` stock plus the `S947BXXU6ZZKN` incremental OTA |
| Vendor, ODM and target hardware files | Galaxy S21+ SM-G996B, AUT (`t2s`) | `G996BXXSJHZC2` |
| ARM32 native libraries for legacy services | Galaxy S21 FE SM-G990E, THL (`r9s`) | `G990EXXSOHZH4` |

The donor runs Android 17. The S21+ uses its own hardware services, partition sizes and recovery model check. Device-specific patches live under `target/t2s`, with Exynos 2100 changes under `platform/exynos2100`. Framework changes use the upstream smali patch format.

## Building

The build creates a private test platform key on first use under `~/.local/share/MonsterROM_NEXT/keys/platform`. Set `MONSTERROM_KEY_DIR` before the first build to choose a different persistent directory. Back up that directory privately and reuse it for subsequent builds and app updates.

Use a Linux filesystem and UN1CA's build dependencies. The S26+ beta is an incremental update and requires the matching stock images. The build expects the resulting firmware tree under `out/fw/SM-S947B_EUX`. The stock target and native-library donor use `out/fw/SM-G996B_AUT` and `out/fw/SM-G990E_THL`.

```bash
source buildenv.sh t2s
prebuilts/samsung/m2sxxx/import-ota.sh /path/to/BZK1-stock.zip /path/to/BZK1-to-ZZKN.zip
run_cmd make_rom -z
```

The importer uses the UN1CA host tools and LineageOS `ota_extractor` on `PATH`. It verifies the payload and ten partition hashes, then exports the original file modes, capabilities and SELinux labels. A directory containing the five reconstructed `.img` files can also be passed directly. On a fresh checkout, initialize the submodules and build the host tools with `./external/make.sh` first. [LineageOS extraction tools](https://github.com/LineageOS/android_prebuilts_extract-tools/tree/aaeb969a477321411279c03799f45ae9f94f770b)

## Project history

This fork starts at UN1CA commit `0c2ea1d6` on the `sixteen` branch. The Exynos 2100 work draws on ExtremeROM and the earlier MonsterROM port.

# Licensing
This project is licensed under the terms of the [GNU General Public License v3.0](LICENSE). External dependencies might be distributed under a different license, such as:
- [android-tools](https://github.com/nmeum/android-tools), licensed under the [Apache License 2.0](https://github.com/nmeum/android-tools/blob/master/LICENSE)
- [apktool](https://github.com/iBotPeaches/Apktool), licensed under the [Apache License 2.0](https://github.com/iBotPeaches/Apktool/blob/master/LICENSE.md)
- [erofs-utils](https://github.com/sekaiacg/erofs-utils/), dual license ([GPL-2.0](https://github.com/sekaiacg/erofs-utils/blob/dev/LICENSES/GPL-2.0), [Apache-2.0](https://github.com/sekaiacg/erofs-utils/blob/dev/LICENSES/Apache-2.0))
- [img2sdat](https://github.com/xpirt/img2sdat), licensed under the [MIT License](https://github.com/xpirt/img2sdat/blob/master/LICENSE)
- [platform_build](https://android.googlesource.com/platform/build/) (ext4_utils, f2fs_utils, signapk), licensed under the [Apache License 2.0](https://source.android.com/docs/setup/about/licenses)

# Contributors
<a href="https://github.com/salvogiangri/UN1CA/graphs/contributors"><img loading="lazy" src="https://contrib.rocks/image?repo=salvogiangri/UN1CA"/></a>

# Credits
A special thanks goes to the following for their invaluable contributions in no particular order:
- **[ShaDisNX255](https://github.com/ShaDisNX255)** for his help, time and for his [NcX ROM](https://github.com/ShaDisNX255/NcX_Stock) which inspired this project
- **[DavidArsene](https://github.com/DavidArsene)** for his help and time
- **[paulowesll](https://github.com/paulowesll)** for his help and support
- **[Simon1511](https://github.com/Simon1511)** for his support and some of the device-specific patches
- **[ananjaser1211](https://github.com/ananjaser1211)** for troubleshooting and his time
- **[Fede2782](https://github.com/Fede2782)** for his contributions and help with Exynos/MTK support
- **[iDrinkCoffee](https://github.com/iDrinkCoffee-TG)** and **[RisenID](https://github.com/RisenID)** for their support
- **[LineageOS Team](https://www.lineageos.org/)** for their original [OTA updater implementation](https://github.com/LineageOS/android_packages_apps_Updater)
- *All the UN1CA project forks, contributors, testers and users ❤️*
