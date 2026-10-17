# Ultra Gaming Mode for Windows (v2.2 - Hardcore Meat Stripper Edition)

Мощный, надежный и полностью автоматизированный инструмент для Windows 10/11, временно переводящий систему в экстремальный игровой режим («Ultra Gaming Mode») на следующую перезагрузку и гарантирующий 100% безопасное восстановление.

---

## 🚀 Что делает Ultra Gaming Mode (v2.2)

### 1. Тотальное отключение фоновых служб (80 служб в базе, 69 на данном ПК):
В Ultra Gaming Mode отключаются:
- **Bluetooth (по запросу пользователя):** `bthserv`, `BthAvctpSvc`, `BTAGService` — полностью отключены.
- **Xbox & Microsoft Store:** `ClipSVC` (лицензии Store), `LicenseManager`, `AppXSvc` (установщик UWP), `GamingServices`, `GamingServicesNet`, `XblAuthManager`, `XblGameSave`, `XboxGipSvc`, `XboxNetApiSvc`.
- **Печать и сканеры:** `Spooler`, `PrintNotify`, `StiSvc` (WIA), `Fax`, `WiaRpc`.
- **Индексация и кэши:** `WSearch` (Windows Search Indexer), `SysMain` (Superfetch).
- **Обновления:** `wuauserv`, `bits`, `dosvc`, `UsoSvc`, `WaaSMedicSvc`, `edgeupdate`, `edgeupdatem`, `gupdate`, `gupdatem`, службы Google Chrome.
- **Телеметрия и диагностика:** `DiagTrack`, `dmwappushservice`, `diagsvc`, `PcaSvc`, `wisvc`.
- **Сетевой шаринг и устаревшие протоколы:** `lmhosts` (NetBIOS), `fdPHost`, `FDResPub`, `IKEEXT`, `PolicyAgent`, `iphlpsvc`, `SSDPSRV`, `UPnPHost`, `smphost`.
- **Фоновые демоны и неигровые утилиты:** `CDPSvc`, `DusmSvc`, `HappService`, `logi_lamparray_service` (RGB-подсветка), `WSLService` (подсистема Linux), `WpnService` (push-уведомления).
- **Биометрия, датчики и виртуальная реальность:** `WbioSrvc`, `PhoneSvc`, `SensorService`, `SensrSvc`, `SensorDataService`, `WalletService`, `RetailDemo`, `SCardSvr`, `TabletInputService`, `SharedRealitySvc`, `MixedRealityOpenXRSvc`, `AJRouter`.

### 2. Приостановка Защитника Windows (Real-Time Protection):
- На время игрового сеанса временно приостанавливается фоновое сканирование файлов, памяти и скриптов Защитником Windows (`DisableRealtimeMonitoring = 1`, `DisableBehaviorMonitoring = 1`, `DisableIOAVProtection = 1`).
- Устраняет причину 90% внезапных микрофризов (stutters) при обращении к игровым архивам и текстурам.
- При выходе из игрового режима защита Windows Defender автоматически восстанавливается в штатный режим.

### 3. Жесткий режим выгрузки фоновых программ:
- **Убиваются принудительно:** браузеры (`firefox`, `chrome`, `msedge`), `Telegram`, `Discord`, `Spotify`, `EpicGamesLauncher`, `CrossDeviceResume` (Связь с телефоном), оверлей AMD (`amdow`, `AMDRSServ`), фоновые виджеты (`msedgewebview2`), торренты и облачные диски.
- **Остаются нетронутыми:** сама запущенная игра, **Steam**, **FACEIT**, драйвер дисплея AMD Radeon (`atieclxx`, `amdfendrsr`), **MSI Afterburner / RivaTuner**, **Process Lasso** (`ProcessGovernor`), **USB-модем iPhone** (`Apple Mobile Device Service`).

### 4. Виджеты Windows 11 и веб-поиск Bing в меню «Пуск»:
- Отключаются виджеты панели задач (`TaskbarDa = 0`, `AllowNewsAndInterests = 0`), выгружая 6 процессов `msedgewebview2.exe`.
- Отключаются онлайн-подсказки Bing и Cortana в меню Пуск (`BingSearchEnabled = 0`, `DisableSearchBoxSuggestions = 1`).

### 5. Режим «Не беспокоить» (Focus Assist) и глушение системных звуков:
- Блокируются всплывающие уведомления (toasts) и системные звуковые сигналы, предотвращая скачки DPC-задержки и загрузку системного звукового микшера `audiodg.exe`.

### 6. Защита микрофона и стабильность DisplayPort:
- Служба приватности аудио `camsvc` защищена в белом списке. Микрофон в Discord и играх работает идеально.
- Служба сетевого RPC `LanmanServer` защищена, предотвращая сбои прав доступа.
- Видеодрайвер AMD Radeon защищен: исключены рискованные твики MMCSS (`Affinity = 0`), устранена очистка памяти при загрузке.

---

## 🎮 Быстрый старт через меню

Запустите **`UltraGamingMode.bat`**:

```
============================================================
           ULTRA GAMING MODE CONTROLLER  v2.1
============================================================

 [1] Arm Ultra Gaming Mode for Next Boot
 [2] Restore Normal Windows State Now
 [3] Flush and Clean RAM Cache Now (Standby List)
 [4] Run System Diagnostic / Pre-Flight Check
 [5] Repair Display & Reset DisplayPort Cache (Emergency Fix)
 [6] Repair Microphone, Steam & Core Services (Instant Fix)
 [7] Check Current Status
 [8] Exit
============================================================
```

- **[1]** Подготовить ПК к экстремальному игровому режиму на следующую перезагрузку.
- **[2]** Вернуть Windows в штатное состояние прямо сейчас (включая Защитник, виджеты и службы).
- **[3]** Освободить оперативную память (Standby List & Working Sets) на лету.
- **[4]** Провести полную диагностику системы.
- **[5]** Экстренный сброс кэша топологии DisplayPort.
- **[6]** Мгновенная разблокировка микрофона, Steam и базовых служб.
- **[7]** Проверить статус.
- **[8]** Выход.
