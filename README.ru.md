<div align="center">

# ⚡ Ultra Gaming Mode для Windows 11
### *Extreme Precision & Hardware Tuning Edition (v2.4)*

**Высокоточный оптимизатор задержек (input latency), фреймтайма и аппаратной части с нулевым риском для Windows 10/11.**  
Временно выгружает фоновый мусор, приостанавливает синхронное сканирование диска Защитником, оптимизирует аппаратную часть AMD Radeon/Ryzen (ULPS, парковка ядер, кэш шейдеров), переводит GPU в режим MSI Mode и гарантирует 100% автоматическое безопасное восстановление при следующей перезагрузке.

[![Windows 11 Supported](https://img.shields.io/badge/Windows-11%20%7C%2010-0078D4?logo=windows&logoColor=white&style=for-the-badge)](https://www.microsoft.com/windows)
[![PowerShell Version](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell&logoColor=white&style=for-the-badge)](https://github.com/PowerShell/PowerShell)
[![Версия](https://img.shields.io/badge/Версия-v2.4--Extreme-FF4500?style=for-the-badge)](https://github.com/RagTagsky/Win11-Gaming-Optimizer/releases)
[![Лицензия: MIT](https://img.shields.io/badge/Лицензия-MIT-success.svg?style=for-the-badge)](LICENSE)
[![Zero-Risk Сторож](https://img.shields.io/badge/Watchdog-HKLM%20RunOnce-blueviolet?style=for-the-badge)](#гарантия-безопасности-и-fail-safe-сторож)
[![Протестировано на AMD](https://img.shields.io/badge/Платформа-Ryzen%20%2B%20Radeon-ED1C24?logo=amd&logoColor=white&style=for-the-badge)](#реальные-тесты-и-телеметрия-движка)

---

[English](README.md) | [Русский](README.ru.md)

</div>

---

## 📑 Содержание
- [Зачем нужен Ultra Gaming Mode?](#зачем-нужен-ultra-gaming-mode)
- [Реальные тесты и телеметрия движка](#реальные-тесты-и-телеметрия-движка)
  - [Характеристики системы и условия тестирования](#характеристики-системы-и-условия-тестирования)
  - [Результаты встроенного профилировщика движка CS2 (Source 2)](#результаты-встроенного-профилировщика-движка-cs2-source-2)
  - [Ключевые выводы](#ключевые-выводы)
- [Архитектура и жизненный цикл](#архитектура-и-жизненный-цикл)
  - [Схема работы оптимизатора](#схема-работы-оптимизатора)
  - [Гарантия безопасности и Fail-Safe сторож](#гарантия-безопасности-и-fail-safe-сторож)
- [Глубокий технический разбор](#глубокий-технический-разбор)
  - [1. Черный список фоновых служб (173 службы)](#1-черный-список-фоновых-служб-173-службы)
  - [2. Неприкосновенный белый список (119 защищенных компонентов)](#2-неприкосновенный-белый-список-119-защищенных-компонентов)
  - [3. Временная приостановка Защитника Windows](#3-временная-приостановка-защитника-windows)
  - [4. Жесткая выгрузка фонового софта](#4-жесткая-выгрузка-фонового-софта)
  - [5. Отключение виджетов Windows 11 и веб-поиска Bing](#5-отключение-виджетов-windows-11-и-веб-поиска-bing)
  - [6. Сетевые твики и оптимизация задержки ядра](#6-сетевые-твики-и-оптимизация-задержки-ядра)
  - [7. Аппаратные оптимизации AMD Radeon и Ryzen (ULPS, кэш шейдеров, парковка ядер)](#7-аппаратные-оптимизации-amd-radeon-и-ryzen-ulps-кэш-шейдеров-парковка-ядер)
  - [8. Режим GPU MSI (Message Signaled Interrupts) и высокий приоритет](#8-режим-gpu-msi-message-signaled-interrupts-и-высокий-приоритет)
  - [9. Диагностика и переключение VBS / HVCI (изоляция ядра)](#9-диагностика-и-переключение-vbs--hvci-изоляция-ядра)
  - [10. Оптимизации файловой системы NTFS](#10-оптимизации-файловой-системы-ntfs)
  - [11. Твики физических сетевых карт (FlowControl и InterruptModeration)](#11-твики-физических-сетевых-карт-flowcontrol-и-interruptmoderation)
  - [12. Очистка оперативной памяти по требованию (Working Sets & Standby List)](#12-очистка-оперативной-памяти-по-требованию-working-sets--standby-list)
  - [13. Инструменты экстренного восстановления (DisplayPort и звук/микрофон)](#13-инструменты-экстренного-восстановления-displayport-и-звукмикрофон)
- [Быстрый старт](#быстрый-старт)
  - [Вариант А: Интерактивное меню (рекомендуется)](#вариант-а-интерактивное-меню-рекомендуется)
  - [Вариант Б: Использование через PowerShell CLI](#вариант-б-использование-через-powershell-cli)
- [Справочник меню и команд CLI](#справочник-меню-и-команд-cli)
- [Структура проекта](#структура-проекта)
- [Системные требования и совместимость](#системные-требования-и-совместимость)
- [Автор и контакты](#автор-и-контакты)
- [Лицензия](#лицензия)

---

## ⚡ Зачем нужен Ultra Gaming Mode?

Современная Windows 11 перегружена сотнями фоновых процессов, сборщиками телеметрии, диагностическими прослушивателями, пользовательскими шаблонами служб и непрерывным сканированием файлов Защитником Windows. В соревновательных киберспортивных дисциплинах (*Counter-Strike 2*, *VALORANT*, *Apex Legends*) эти фоновые всплески приводят к:
- **Скачкам DPC-задержки (Deferred Procedure Call):** Вызваны энергосберегающими состояниями сетевых карт (`*EEE`) и конкуренцией за очереди мультимедийного планировщика.
- **Микрофризам при загрузке ассетов:** Защитник Windows перехватывает синхронные системные вызовы ввода-вывода при подгрузке текстур, шейдеров и моделей.
- **Потерям плавности на границах кадров (Frame Boundary Spikes):** Вторичные системные потоки перехватывают ядра ЦП у основного потока рендеринга.
- **Провалам 1% Low FPS:** Ощутимые подергивания картинки и "тяжелый" прицел даже при высоком среднем FPS.

**Ultra Gaming Mode v2.3** устраняет эти проблемы без деструктивного вмешательства в систему. В отличие от сомнительных твикеров и скриптов-деблоатеров, которые ломают систему навсегда, ломают доступ к микрофону или вызывают черные экраны на мониторах DisplayPort, Ultra Gaming Mode использует **обратимый цикл на базе снимков состояния**:

```
[Штатная Windows] ──(Подготовка)──> [Снимок системы JSON] ──(Перезагрузка)──> [Ultra Gaming Mode]
        ▲                                                                              │
        │                                                                              │
        └────────────────────(Сторож RunOnce / Восстановление)─────────────────────────┘
```

---

## 📊 Реальные тесты и телеметрия движка

Все измерения зафиксированы с помощью встроенного в движок низкоуровневого инструмента профилирования в реальном матче 5v5 в равных условиях.

### Характеристики системы и условия тестирования
| Компонент | Значение |
|:---|:---|
| **Процессор (CPU)** | AMD Ryzen 5 5600X (6 ядер / 12 потоков @ 4.6 GHz) |
| **Видеокарта (GPU)** | AMD Radeon RX 6600 (8 GB GDDR6) |
| **Оперативная память (RAM)** | 32 GB DDR4 (Dual Channel 3600 MHz CL16) |
| **Операционная система** | Windows 11 Pro (x64) |
| **Тестовая игра** | *Counter-Strike 2* (движок Valve Source 2) |
| **Разрешение экрана** | 1440x1080 (4:3 Stretched) |
| **Настройки графики** | Киберспортивные низкие (Anti-Lag / Reflex включен) |
| **Инструмент замера** | Встроенный профилировщик движка Valve Source 2 `VProfLite` |
| **Объем выборки** | **59 467 непрерывных кадров** (~121.2 секунды реального активного файта) |

---

### Результаты встроенного профилировщика движка CS2 (Source 2)

| Метрика | Обычная Windows 11 | Ultra Gaming Mode v2.3 | Разница / Прирост | Практическое влияние на игру |
|:---|:---:|:---:|:---:|:---|
| **1% Low FPS (P1)** | **169.6 FPS** | **187.5 FPS** | **+17.9 FPS (+10.6%)** | **Идеальная плавность доводки прицела в смоках и плотных файтах** |
| **Средний FPS (Average)** | **473.1 FPS** | **493.0 FPS** | **+19.9 FPS (+4.2%)** | Увеличение общей производительности и пропускной способности движка |
| **Средний FrameTime** | **2.11 мс** | **2.03 мс** | **-0.08 мс** | Снижение базового времени отрисовки одного кадра |
| **Плотность кадров 99% (P99 FrameTotal)** | **5.90 мс** | **5.33 мс** | **-0.57 мс (-9.7%)** | Устранение очередей отрисовки в 99% самых тяжелых кадров |
| **Frame Boundary (P95 Sync Spikes)** | **4.50 мс** | **3.10 мс** | **-1.40 мс (-31.1%)** | **Снижение спайков на 31.1%! Исчезли задержки синхронизации потоков ЦП** |
| **Client Rendering (P95 Render Spikes)** | **4.80 мс** | **3.40 мс** | **-1.40 мс (-29.2%)** | **Отрисовка сцены и вызовы draw calls стали на 29.2% стабильнее** |
| **Present_RenderDevice (P95 Input Queue)** | **2.48 мс** | **2.19 мс** | **-0.29 мс (-11.7%)** | **Снижение задержки вывода кадра и отклика ввода мыши на 11.7%** |
| **Server Simulation (P95 Local Tickrate)** | **3.25 мс** | **3.11 мс** | **-0.14 мс (-4.3%)** | Более стабильный расчет локального тикрейта и суб-тиков |
| **Server Game (P95 Game Logic)** | **2.84 мс** | **2.70 мс** | **-0.14 мс (-4.9%)** | Быстрый расчет игровой физики, регистрации попаданий и коллизий |
| **Panorama UI (P99 UI Latency)** | **0.46 мс** | **0.14 мс** | **-0.32 мс (в 3.3 раза быстрее / -69.5%)** | Мгновенное обновление радара, киллфида и прицела без лагов интерфейса |

### Ключевые выводы
1. **Падение спайков Frame Boundary на -31.1%:** Движок Source 2 тратит на треть меньше времени на ожидание планировщика потоков ядра Windows между кадрами.
2. **Прирост редких событий на +17.9 FPS (1% Low):** Показатель 1% Low перешагнул отметку 187 кадров/с, устраняя микрозадержки при зажиме и резких фликах.
3. **Задержка интерфейса Panorama UI уменьшилась в 3.3 раза:** Полное устранение помех со стороны системного компоновщика Windows и виджетов снизило отклик HUD до рекордных 0.14 мс.

---

## 🛠 Архитектура и жизненный цикл

### Схема работы оптимизатора

```
                 +-----------------------------------------+
                 |       Запуск UltraGamingMode.bat        |
                 +-----------------------------------------+
                                      │
                       [1] Подготовка к следующему входу
                                      ▼
                 +-----------------------------------------+
                 | 1. Создание снимка системы (JSON)       |
                 | 2. Подавление автозапуска и виджетов    |
                 | 3. Регистрация триггера загрузки SYSTEM |
                 +-----------------------------------------+
                                      │
                             Перезагрузка ПК
                                      ▼
                 +-----------------------------------------+
                 | Планировщик от имени NT AUTHORITY\SYSTEM|
                 | запускает ApplyBootMode:                |
                 | - Отключает 173 службы из черного списка|
                 | - Приостанавливает сканы Защитника      |
                 | - Оптимизирует сеть (TCPNoDelay, *EEE)  |
                 | - Взводит сторож HKLM RunOnce           |
                 +-----------------------------------------+
                                      │
                         Игровая сессия пользователя
                                      │
             ┌────────────────────────┴────────────────────────┐
             ▼                                                 ▼
+---------------------------+                     +---------------------------+
| Обычная перезагрузка ПК   |                     | Выбор пункта [2] Restore  |
| Сторож RunOnce полностью  |                     | (Мгновенный ручной возврат|
| восстанавливает систему   |                     | в штатное состояние)      |
+---------------------------+                     +---------------------------+
             │                                                 │
             └────────────────────────┬────────────────────────┘
                                      ▼
                 +-----------------------------------------+
                 | Windows возвращена в 100% штатный вид:  |
                 | - Исходные типы запуска служб возвращены|
                 | - Защита в реальном времени включена    |
                 | - Виджеты, поиск и автозапуск активны   |
                 +-----------------------------------------+
```

### Гарантия безопасности и Fail-Safe сторож
В отличие от деструктивных скриптов, оставляющих систему поврежденной при любом сбое, в Ultra Gaming Mode заложена аппаратная отказоустойчивость:
1. **Точные снимки состояния (`Backups\active_state.json`):** До внесения малейших правок исходный тип запуска каждой службы (`Manual`, `Auto`, `Disabled`), ярлыки автозагрузки, настройки UWP и сетевые параметры протоколируются в JSON-файле.
2. **Сторожевой таймер ядра `HKLM\RunOnce`:** В ветке `HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce` регистрируется сторож `*UltraGamingModeRestore`.
3. **Защита от сбоев питания и синих экранов:** Если во время игры внезапно отключится электричество или произойдет краш, Windows при следующем старте автоматически запустит сторож, распакует исходный снимок и вернет систему в нормальное состояние без участия пользователя.

---

## 🔬 Глубокий технический разбор

### 1. Черный список фоновых служб (173 службы)
Сформирован с предельной точностью для устранения лишних переключений контекста процессора:
- **Телеметрия и корпоративная диагностика:** `DiagTrack`, `dmwappushservice`, `DPS` (Diagnostic Policy Service), `wmiApSrv`, `pla` (Performance Logs), `TroubleshootingSvc`, `wuqisvc`, `WSAIFabricSvc` (Windows AI Fabric).
- **Удаленный рабочий стол и Hyper-V:** `TermService`, `SessionEnv`, `UmRdpService`, `WinRM`, `HvHost`, все компоненты интеграции `vmic*`, `MSiSCSI`, `SNMPTrap`, `RpcLocator`.
- **Резервное копирование и история файлов:** `fhsvc` (File History), `wbengine` (Block Level Backup), `SDRSVC` (Windows Backup), `CloudBackupRestoreSvc`, `OneSyncSvc`.
- **Печать и сканеры:** `Spooler`, `PrintNotify`, `PrintScanBrokerService`, `PrintDeviceConfigurationService`, `PrintWorkflowUserSvc`, `StiSvc` (WIA), `Fax`, `WiaRpc`.
- **Bluetooth (выборочно):** `bthserv`, `BthAvctpSvc`, `BTAGService`, `BluetoothUserService` (легко восстанавливаются в один клик при использовании геймпада).
- **Xbox и магазин Microsoft Store:** `ClipSVC`, `LicenseManager`, `AppXSvc`, `GamingServices`, `GamingServicesNet`, `XblAuthManager`, `XblGameSave`, `XboxGipSvc`, `XboxNetApiSvc`, `InstallService`, `PushToInstall`.
- **Пользовательские службы синхронизации Windows 11:** `CaptureService`, `BcastDVRUserService` (буфер GameDVR), `CDPUserSvc`, `DevicePickerUserSvc`, `DevicesFlowUserSvc`, `DeviceAssociationBrokerSvc`, `SmsRouter`, `MessagingService`, `PenService`, `UserDataSvc`, `UnistoreSvc`, `cbdhsvc`, `NPSMSvc`.
- **Индексация и дисковые кэши:** `WSearch` (Windows Search Indexer), `SysMain` (Superfetch).
- **Службы обновлений:** `wuauserv`, `bits`, `dosvc`, `UsoSvc`, `WaaSMedicSvc`, `edgeupdate`, `edgeupdatem`, `gupdate`, `gupdatem`.
- **Мобильный хотспот, сотовая сеть и геолокация:** `icssvc`, `autotimesvc`, `lfsvc`, `WFDSConMgrSvc`.
- **Сторонний софт:** `EABackgroundService` (фоновая телеметрия EA App), `LibreOfficeMaintenance`.

### 2. Неприкосновенный белый список (119 защищенных компонентов)
Каждая операция строго сверяется с защищенным белым списком:
- **Прямой низколатентный ввод:** `GameInputSvc` (API прямого ввода Windows 11), `hidserv` (стек HID, сохраняющий частоту опроса мыши 1000/4000/8000 Гц и работу макросов), `TextInputManagementService` (клавиатурный движок и внутриигровой чат).
- **Звук и конфиденциальность микрофона:** `Audiosrv`, `AudioEndpointBuilder`, `camsvc` (**Capability Access Manager Service** — защищает доступ к микрофону, гарантируя, что Discord, голосовой чат Steam и игра никогда не потеряют микрофон), `ApxSvc`, `midisrv`, `QWAVE`.
- **Сеть и мобильный модем:** `Dhcp`, `Dnscache`, `LanmanWorkstation`, `LanmanServer` (предотвращает сбои RPC-сессий), `NlaSvc`, `netprofm`, `WlanSvc`, `Wcmsvc`, `Netman`, `nsi`, `Apple Mobile Device Service` (обеспечивает бесперебойную работу USB-модема iPhone на Ethernet 2).
- **Античиты и лаунчеры:** `FACEIT`, `FACEITService`, `Steam Client Service`, `Rockstar Service`, `vgk`, `vgc` (Riot Vanguard), `EasyAntiCheat`, `BEService` (BattlEye).
- **Драйверы видеокарты и оборудования:** `AMD External Events Utility`, `AMD Crash Defender Service`, `GraphicsPerfSvc`, `DisplayEnhancementService`, `DispBrokerDesktopSvc`, `ProcessGovernor` (Process Lasso).
- **Безопасность системы и UAC:** `Appinfo` (эскалация прав администратора), `StateRepository`, `UserManager`, `TokenBroker`, `wlidsvc`, `Schedule`, `TimeBrokerSvc`, `Winmgmt`.

### 3. Временная приостановка Защитника Windows
- На время действия режима сканирование в реальном времени временно приостанавливается (`DisableRealtimeMonitoring = 1`, `DisableBehaviorMonitoring = 1`, `DisableIOAVProtection = 1`, `DisableScriptScanning = 1`).
- Полностью исключает микрофризы от дисковых блокировок при подгрузке текстур и карт.
- При выходе из режима защита автоматически включается обратно.

### 4. Жесткая выгрузка фонового софта
- **Принудительно завершаются:** Браузеры (`firefox`, `chrome`, `msedge`), `Telegram`, `Discord`, `Spotify`, `EpicGamesLauncher`, `CrossDeviceResume` (Связь с телефоном), видеооверлей AMD (`amdow`, `AMDRSServ`), виджеты (`msedgewebview2`), облачные диски (`GoogleDriveFS`), фоновые апдейтеры.
- **Строго защищены:** Запущенная игра, **Steam**, **FACEIT Client**, видеодрайвер AMD Radeon (`atieclxx`, `amdfendrsr`), **MSI Afterburner / RivaTuner**, **Process Lasso** (`ProcessGovernor`), **Apple Mobile Device Service** (USB-модем).

### 5. Отключение виджетов Windows 11 и веб-поиска Bing
- Отключаются виджеты панели задач (`TaskbarDa = 0`, `AllowNewsAndInterests = 0`), что выгружает до 6 скрытых фоновых процессов `msedgewebview2.exe`.
- Отключаются онлайн-подсказки Bing в меню Пуск (`BingSearchEnabled = 0`, `DisableSearchBoxSuggestions = 1`), разгружая ресурсы при работе с интерфейсом.

### 6. Сетевые твики и оптимизация задержки ядра
- **Отключение алгоритма Нагла:** Устанавливает `TCPNoDelay = 1` и `TcpAckFrequency = 1` для сетевых интерфейсов, устраняя буферизацию пакетов в мультиплеере.
- **Отключение Energy-Efficient Ethernet (*EEE):** Запрещает сетевой карте переходить в энергосберегающий сон (`*EEE = 0`, `EnableGreenEthernet = 0`), устраняя микроразрывы и скачки пинга.

### 7. Аппаратные оптимизации AMD Radeon и Ryzen (ULPS, кэш шейдеров, парковка ядер)
- **Отключение AMD ULPS (Ultra Low Power State):** Автоматически определяет ключи драйвера AMD Radeon в `HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\000*` и устанавливает `EnableUlps = 0`. Предотвращает микрофризы глубокого сна GPU, задержку пробуждения второго монитора и провалы частот (исходное значение сохраняется в снимке и восстанавливается при выходе).
- **Очистка кэша шейдеров DirectX и Vulkan:** Пункт **`[7]`** безопасно удаляет поврежденный или раздутый кэш шейдеров AMD и DirectX (`%LOCALAPPDATA%\AMD\DxCache`, `VkCache`, `DxcCache`, `DX9Cache`, `OglCache`, `%LOCALAPPDATA%\D3DSCache`), полностью устраняя микрофризы от компиляции шейдеров и выпадение кадров в соревновательных играх, таких как *CS2*.
- **Отключение парковки ядер Ryzen (Core Parking):** Автоматически настраивает активную схему электропитания, выставляя минимальное число активных ядер процессора на 100% (`powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMINCORES 100`). Это удерживает все 6 физических ядер и 12 потоков процессора Ryzen 5 5600X в постоянной готовности и исключает задержки межъядерных переходов CCX.

### 8. Режим GPU MSI (Message Signaled Interrupts) и высокий приоритет
- Находит дискретный графический адаптер PCI (AMD Radeon RX 6600) и настраивает режим прерываний Message Signaled Interrupts (`MSISupported = 1`) в ветке `Device Parameters\Interrupt Management\MessageSignaledInterruptProperties`.
- Настраивает политику приоритета прерываний (`DevicePriority = 3`, высокий приоритет) в ветке `Device Parameters\Interrupt Management\Affinity Policy`.
- Заменяет устаревший построчный механизм IRQ-шеринга (где GPU делит линию прерываний с другими устройствами) на прямую запись в память через MSI. Это исключает аппаратные конфликты и снижает время доставки кадров DPC от видеокарты к процессору. Исходные значения сохраняются и восстанавливаются.

### 9. Диагностика и переключение VBS / HVCI (изоляция ядра)
- Диагностирует статус Virtualization-Based Security (VBS) и Hypervisor-Enforced Code Integrity (HVCI / Целостность памяти) через пространство WMI/CIM `root\Microsoft\Windows\DeviceGuard` (`Win32_DeviceGuard`).
- Пункт **`[8]`** предоставляет безопасное переключение для отключения или включения VBS/HVCI в системном реестре (`EnableVirtualizationBasedSecurity` и `HypervisorEnforcedCodeIntegrity\Enabled`), снижая оверхед виртуализации CPU и выводя предупреждение о необходимости перезагрузки.

### 10. Оптимизации файловой системы NTFS
- Применяет команду `fsutil behavior set disablelastaccess 1`, запрещая Windows обновлять отметку времени последнего доступа к файлам при каждом чтении, снижая паразитную нагрузку на SSD во время потоковой загрузки игровых текстур.
- Применяет `fsutil behavior set disable8dot3 1`, отключая генерацию коротких имен формата DOS 8.3 для ускорения чтения директорий. Обе настройки сохраняются в снимке и корректно восстанавливаются в штатном режиме.

### 11. Твики физических сетевых карт (FlowControl и InterruptModeration)
- Для физических Ethernet и Wi-Fi адаптеров автоматически отключает `*FlowControl` (устраняет искусственные паузы передачи, вызывающие спайки пинга) и `*InterruptModeration` (мгновенно передает входящие пакеты процессору для минимально возможной сетевой задержки).
- **Железная безопасность:** Полностью игнорирует и защищает адаптеры Apple Mobile Device Ethernet (`Ethernet 2` для USB-модема iPhone) и туннели Wintun (`wwan99`).

### 12. Очистка оперативной памяти по требованию (Working Sets & Standby List)
- Использует прямой вызов Win32 API `psapi.dll!EmptyWorkingSet`.
- Сбрасывает рабочий набор второстепенных процессов в кэш ожидания, запускает сборщик мусора и освобождает сотни мегабайт физической памяти на лету без перезапуска ПК.

### 13. Инструменты экстренного восстановления (DisplayPort и звук/микрофон)
- **Пункт [5] Сброс топологии DisplayPort:** Очищает поврежденный кэш конфигурации мониторов в реестре `HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers` (`Configuration`, `Connectivity`, `ScaleFactors`), нормализует приоритеты MMCSS (`Affinity = 0`), перезапускает службы дисплея и принудительно инициирует свежее согласование DisplayPort Link Training.
- **Пункт [6] Разблокировка микрофона и базовых служб:** Мгновенно восстанавливает и запускает `camsvc` (исправляет блокировку доступа к микрофону в Discord/CS2), службу RPC `LanmanServer` и переводит службы Steam и Bluetooth в режим ручного запуска.

---

## 🚀 Быстрый старт

### Вариант А: Интерактивное меню (рекомендуется)

1. Клонируйте или скачайте репозиторий:
   ```cmd
   git clone https://github.com/RagTagsky/Win11-Gaming-Optimizer.git
   cd Win11-Gaming-Optimizer
   ```
2. Нажмите правой кнопкой мыши по **`UltraGamingMode.bat`** и выберите **«Запуск от имени администратора»** (при необходимости файл запросит повышение прав автоматически).
3. Выберите **`[1] Arm Ultra Gaming Mode for Next Boot`**.
4. Перезагрузите компьютер. Система запустится в очищенном Ultra Gaming Mode.
5. После завершения игры запустите **`UltraGamingMode.bat`** и выберите **`[2] Restore Normal Windows State Now`** (либо просто перезагрузите ПК — сторож вернет систему в штатное состояние сам).

```
============================================================
           ULTRA GAMING MODE CONTROLLER  v2.4
============================================================

 [1] Arm Ultra Gaming Mode for Next Boot
 [2] Restore Normal Windows State Now
 [3] Flush and Clean RAM Cache Now (Standby List)
 [4] Run System Diagnostic / Pre-Flight Check
 [5] Repair Display + Reset DisplayPort Cache (Emergency Fix)
 [6] Repair Microphone, Steam + Core Services (Instant Fix)
 [7] Purge AMD / DirectX / Vulkan Shader Cache
 [8] Check & Toggle VBS / HVCI (Core Isolation)
 [9] Check GPU MSI Mode & Device Priority Status
[10] Check Current Status
[11] Exit
============================================================
```

---

### Вариант Б: Использование через PowerShell CLI

Откройте PowerShell от имени Администратора:

```powershell
# Проверить текущий статус системы и количество фоновых служб
powershell.exe -ExecutionPolicy Bypass -File .\UltraGamingMode.ps1 -Action Status

# Запустить предполетную диагностику
powershell.exe -ExecutionPolicy Bypass -File .\UltraGamingMode.ps1 -Action Diagnostic

# Подготовить игровой режим на следующую перезагрузку
powershell.exe -ExecutionPolicy Bypass -File .\UltraGamingMode.ps1 -Action Enable

# Очистить кэш шейдеров AMD / DirectX / Vulkan
powershell.exe -ExecutionPolicy Bypass -File .\UltraGamingMode.ps1 -Action FlushShaderCache

# Проверить и переключить VBS / HVCI (Изоляция ядра)
powershell.exe -ExecutionPolicy Bypass -File .\UltraGamingMode.ps1 -Action ToggleVBS

# Проверить статус режима GPU MSI и приоритет прерываний
powershell.exe -ExecutionPolicy Bypass -File .\UltraGamingMode.ps1 -Action GpuMsiStatus

# Освободить оперативную память прямо сейчас
powershell.exe -ExecutionPolicy Bypass -File .\UltraGamingMode.ps1 -Action CleanMemory

# Вернуть систему в исходное штатное состояние
powershell.exe -ExecutionPolicy Bypass -File .\UltraGamingMode.ps1 -Action Restore

# Экстренный сброс кэша DisplayPort и видеодрайвера
powershell.exe -ExecutionPolicy Bypass -File .\UltraGamingMode.ps1 -Action RepairDisplay

# Экстренное восстановление микрофона (camsvc) и служб Steam
powershell.exe -ExecutionPolicy Bypass -File .\UltraGamingMode.ps1 -Action RepairServices
```

---

## 🕹 Справочник меню и команд CLI

| Пункт меню | Команда CLI | Описание |
|:---:|:---|:---|
| **`[1]`** | `-Action Enable` | Создает снимок системы (службы, ULPS, MSI, NTFS, Core Parking, сетевые карты), подавляет автозапуск софта и регистрирует задачу загрузки от имени SYSTEM. |
| **`[2]`** | `-Action Restore` | Возвращает все 173 службы и настройки железа (ULPS, MSI, Core Parking, NTFS, сеть) к исходному состоянию, включает Защитник Windows, удаляет задачи загрузки и восстанавливает автозапуск. |
| **`[3]`** | `-Action CleanMemory` | Вызывает `EmptyWorkingSet` через Win32 API для сброса кэша и освобождения RAM на лету. |
| **`[4]`** | `-Action Diagnostic` | Полный аудит: проверка прав администратора, схем питания и парковки ядер Ryzen, MMCSS, сетевых адаптеров, AMD ULPS, кэша шейдеров, GPU MSI, VBS/HVCI, NTFS, защиты белого списка и фоновых служб. |
| **`[5]`** | `-Action RepairDisplay` | Экстренное исправление: очистка кэшей топологии мониторов в реестре и сброс настроек планировщика MMCSS. |
| **`[6]`** | `-Action RepairServices`| Экстренное исправление: восстанавливает и запускает `camsvc` (доступ к микрофону), `LanmanServer` (RPC) и Steam. |
| **`[7]`** | `-Action FlushShaderCache`| Очищает кэши шейдеров AMD DirectX, Vulkan и D3D (`DxCache`, `VkCache`, `DxcCache`, `DX9Cache`, `OglCache`, `D3DSCache`) для устранения микрофризов компиляции шейдеров. |
| **`[8]`** | `-Action ToggleVBS` | Проверяет и переключает VBS / HVCI (целостность памяти) в реестре для устранения оверхеда виртуализации. |
| **`[9]`** | `-Action GpuMsiStatus` | Показывает статус режима Message Signaled Interrupts (MSI) видеокарты и приоритет прерываний (`DevicePriority = 3`). |
| **`[10]`**| `-Action Status` | Показывает текущий статус системы (`Normal`, `Armed`, `GameMode_Active`, `Restored`), число активных служб, состояние Core Parking, AMD ULPS, GPU MSI и VBS. |
| **`[11]`**| `Exit` | Закрывает командное меню. |

---

## 📂 Структура проекта

```
Win11-Gaming-Optimizer/
│
├── UltraGamingMode.bat              # Интерактивное меню с автоматическим запросом прав
├── UltraGamingMode.ps1              # Основной оркестратор и контроллер PowerShell
├── README.md                        # Документация и тесты на английском языке
├── README.ru.md                     # Документация и тесты на русском языке
├── LICENSE                          # Открытая лицензия MIT
│
├── Config/
│   ├── services_blacklist.json      # 173 фоновые службы под отключение
│   ├── services_whitelist.json      # 119 строго защищенных компонентов
│   └── startup_apps.json            # Правила автозагрузки и фонового софта
│
├── Core/
│   ├── ServiceManager.ps1           # Безопасное управление службами с защитой белого списка
│   ├── StateEngine.ps1              # Снимки системы, сохранение и откат состояния
│   └── SystemOptimizer.ps1          # Управление питанием, MMCSS, сетью, RAM и Защитником
│
└── Backups/
    └── active_state.json            # Динамический снимок текущей сессии (автоматический)
```

---

## 💻 Системные требования и совместимость

- **Операционная система:** Windows 11 (21H2, 22H2, 23H2, 24H2) или Windows 10 (20H2+) 64-bit.
- **PowerShell:** PowerShell 5.1 (встроен в Windows) или PowerShell 7+.
- **Права доступа:** Требуются права Администратора для управления службами и системным реестром.
- **Совместимость с оборудованием:**
  - Полная поддержка процессоров AMD Ryzen и Intel Core.
  - Полная поддержка видеокарт AMD Radeon, NVIDIA GeForce и Intel Arc.
  - Безопасно для мониторов с поддержкой DisplayPort DSC (Display Stream Compression) и HDMI 2.1.
  - Полная поддержка мышей с высокой частотой опроса (1000–8000 Гц) благодаря защите `hidserv` и `GameInputSvc`.
- **Совместимость с античитами:** 100% совместимо с FACEIT, Riot Vanguard (*VALORANT*), EasyAntiCheat (*Apex Legends*, *Fortnite*), BattlEye (*Rainbow Six Siege*) и Valve Anti-Cheat (*CS2*).

---

## 👤 Автор и контакты

- **Разработчик:** RagTagsky
- **Официальный сайт:** [ragtagsky.xyz](https://ragtagsky.xyz)
- **Репозиторий проекта:** [github.com/RagTagsky/Win11-Gaming-Optimizer](https://github.com/RagTagsky/Win11-Gaming-Optimizer)

---

## 📄 Лицензия

Проект распространяется под открытой лицензией **MIT** — подробности в файле [LICENSE](LICENSE).  
Вы можете свободно использовать, модифицировать и распространять данное программное обеспечение для личных и соревновательных игровых систем.
