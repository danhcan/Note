# Note

## Flutter app dieu khien ESP32-C3 (3 gang cong tac kinh)

Da cap nhat app Flutter trong `flutter_app/` theo giao dien cong tac kinh 3 gang, co:

- Dieu khien 3 thiet bi (`Den`, `Quat`, `Switch 3`).
- Dong bo trang thai thuc khi mo app (auto goi `/status` + dong bo dinh ky moi 3 giay).
- Dieu khien giong noi (bat/tat tung kenh, all on/off, hen gio theo phut).
- Hen gio tung thiet bi.
- Tu dong tim ESP32-C3, khong can nhap IP (uu tien mDNS `esp32c3.local`, fallback AP mode).
- Hien thi trang thai ket noi (WiFi/IP) ngay tren man hinh.
- Co nut `Cap nhat phan mem` trong `Setting` (goi API firmware tren ESP32-C3).

## API yeu cau tren ESP32-C3

- `GET /status`
- `POST /toggle` body: `{ "id": 0..2, "state": true|false }`
- `POST /all` body: `{ "state": true|false }`
- `POST /timer` body: `{ "id": 0..2, "minutes": number }`
- `GET /fw` (kiem tra firmware)
- `POST /update` (kich hoat cap nhat OTA)

## Chay app

```bash
cd flutter_app
flutter pub get
flutter run
```

## Plugin da dung

- `http`
- `multicast_dns`
- `speech_to_text`
