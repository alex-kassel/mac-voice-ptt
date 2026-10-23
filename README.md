# Dictaphone (macOS Native Swift)

Нативная системная Push-to-Talk утилита для macOS.
Зажимаешь клавишу → говоришь в микрофон → отпускаешь → распознанный текст автоматически вставляется в позицию курсора через OpenAI `gpt-4o-mini-transcribe`.

---

## Преимущества нативной Swift-версии

- **Размер бандла**: всего **~270 КБ** (вместо сотен мегабайт у Python + venv).
- **Потребление памяти**: **~15–25 МБ RAM** (вместо 120+ МБ у Python).
- **Мгновенный отклик**: чистые системные фреймворки `AppKit`, `AVFoundation`, `CoreGraphics`, `ServiceManagement`.
- **Нормальная установка и удаление**: приложение собирается в стандартный файл `Dictaphone.app`, который перетаскивается в `/Applications`.
- **Нативный автозапуск**: переключатель `Launch at Login` прямо в меню-баре использует системный `SMAppService` (отображается в *Системные настройки → Основные → Объекты входа*).
- **Права доступа**: macOS выдаёт разрешения Accessibility и Microphone **напрямую приложению Dictaphone.app**, и они не слетают при обновлении системного Python или терминала.
- **Ввод API-ключа через интерфейс**: пункт меню `OpenAI API Key...` открывает нативный диалог (также поддерживается чтение из `~/.dictaphone/.env`).

---

## Архитектура проекта

```
mac-voice-ptt-swift/
├── Package.swift                  # Описание Swift Package
├── Makefile                       # Команды сборки, установки и удаления
├── Resources/
│   └── Info.plist                 # Настройки бандла (LSUIElement, разрешения)
├── Sources/
│   └── Dictaphone/
│       ├── main.swift             # Точка входа, защита от дубликатов (flock)
│       ├── AppDelegate.swift      # Координатор жизненного цикла приложения
│       ├── Config.swift           # Хранилище настроек (~/.dictaphone/config.json)
│       ├── HotkeyManager.swift    # CoreGraphics event tap для Push-to-Talk
│       ├── AudioRecorder.swift    # Нативная запись аудио в 16kHz WAV через AVFoundation
│       ├── Transcriber.swift      # URLSession multipart клиент к OpenAI API
│       ├── OverlayPanel.swift     # Плавающий полупрозрачный HUD-таймер с красной точкой
│       ├── Paster.swift           # Эмуляция Cmd+V через CGEvent с сохранением буфера
│       ├── MenuBarController.swift# Иконка ◉ в строке меню и контекстное меню
│       └── LaunchAtLoginManager.swift # Управление автозапуском через SMAppService
└── scripts/
    ├── build_app.sh               # Сборка и подпись Dictaphone.app
    ├── install.sh                 # Установка в /Applications и первый запуск
    └── uninstall.sh               # Удаление из /Applications
```

---

## Быстрый старт

### 1. Сборка приложения

```bash
cd mac-voice-ptt-swift
make app
```
В результате в папке `build/` появится готовый файл `Dictaphone.app`.

### 2. Установка в `/Applications`

```bash
make install
```
Скрипт автоматически:
1. Остановит старые процессы Dictaphone (включая python-версию).
2. Скопирует `Dictaphone.app` в `/Applications`.
3. Снимет атрибут карантина (`quarantine`).
4. Запустит приложение.

### 3. Разрешения macOS (только при первом запуске)

1. **Accessibility**: *Системные настройки → Конфиденциальность и безопасность → Универсальный доступ* → разрешить **Dictaphone**.
2. **Microphone**: *Системные настройки → Конфиденциальность и безопасность → Микрофон* → разрешить **Dictaphone**.

### 4. Автозапуск при старте системы

Нажмите на иконку `◉` в строке меню и включите галочку **Launch at Login**.

---

## Удаление приложения

```bash
make uninstall
```
или просто перетащите `Dictaphone.app` из `/Applications` в Корзину.
