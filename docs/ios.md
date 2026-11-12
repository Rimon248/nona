# Нона для iPhone и iPad

## Текущий этап

iOS-приложение использует общий Flutter-интерфейс, вход через Keycloak, регистрацию устройства, проверку подписанной конфигурации и защищённое хранилище iOS. Зарегистрирован URL-адрес возврата после входа `ru.basketref.nona://oauth2redirect`. Предварительная сборка создаётся командой `apps/client/build-ios-preview.sh`; флаг `--no-codesign` означает, что результат нельзя установить на обычный iPhone.

Кнопка VPN пока недоступна: существующий Android/Windows/macOS TUN нельзя просто перенести в приложение iOS. Следующий этап — отдельный Packet Tunnel app extension с `NEPacketTunnelProvider`, передача в него персональной конфигурации через Keychain access group и адаптер Xray для чтения/записи пакетов `packetFlow`. Главному приложению и extension понадобятся разрешение Network Extensions (Packet Tunnel), отдельные bundle ID и подходящие профили подписи. Нельзя включать системный VPN до фактического запуска движка и успешной установки сетевых настроек.

В приложении надо сохранить порядок Hysteria2 → VLESS+REALITY → резервный узел, проверять настоящий трафик, прекращать соединение по кнопке «Отключить» без зависимости от действительности токена входа, а после перезапуска брать состояние из Network Extension. Маршруты российских сайтов требуют DNS-правил и проверки на реальном устройстве. Произвольное исключение приложений на обычном iPhone не предусмотрено.

## Как распространять вне App Store

| Способ | Для кого | Что нужно |
| --- | --- | --- |
| Xcode на личный iPhone | Разработчик и собственные устройства | Бесплатный Apple Account подходит для разработки и запуска через Xcode; для Packet Tunnel нужна возможность подписать требуемый entitlement. Установка на чужие устройства так не масштабируется. |
| TestFlight | Ограниченная бета для пользователей | Apple Developer Program; до 10 000 внешних тестировщиков, проверка первого билда Apple, срок действия билда 90 дней. Приложение не публикуется в каталоге App Store, но проходит через инфраструктуру Apple. |
| Ad Hoc | Известные устройства небольшой группы | Apple Developer Program, сертификат, профиль и заранее зарегистрированные UDID; Apple допускает до 100 iPhone за год членства. IPA можно передавать вне App Store только зарегистрированным устройствам. |
| Enterprise | Сотрудники собственной организации | Apple Developer Enterprise Program; не предназначен для пользователей публичного VPN-сервиса. |
| Альтернативный магазин или сайт в ЕС | Пользователи, которые отвечают региональным условиям Apple | Apple Developer Program, условия альтернативной дистрибуции, нотариализация и отдельное разрешение для распространения с сайта. Это не общий способ установки для пользователей в России. |

Для первых внешних пользователей наиболее практичен TestFlight после оформления Apple Developer Program. Для небольшой закрытой группы с известными устройствами подходит Ad Hoc. Свободная загрузка IPA с GitHub без подписи и регистрации устройства не устанавливается на обычный iPhone.

Источники Apple: [Packet Tunnel](https://developer.apple.com/documentation/networkextension/nepackettunnelprovider), [настройка Network Extensions](https://developer.apple.com/documentation/xcode/configuring-network-extensions), [TestFlight](https://developer.apple.com/testflight/), [Ad Hoc](https://developer.apple.com/help/account/devices/devices-overview/), [веб-распространение в ЕС](https://developer.apple.com/documentation/marketplacekit/distributing-your-app-from-your-website).
