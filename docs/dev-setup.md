# Cài môi trường trên một máy mới

Hướng dẫn chạy dự án trên **một máy hoàn toàn mới**, chỉ có kết nối GitHub: web Rails (repo này), trang thử nghiệm
qua tunnel, và app Android ([vn_badminton_mobile](https://github.com/itssamuelnguyen-vn/vn_badminton_mobile)).
Dự án chưa dùng Docker cho môi trường phát triển nên phải cài từng thứ; làm lần lượt từ trên xuống.

> Cập nhật: 24/10/2026. Phiên bản đang dùng: Ubuntu 24.04 (WSL2), Ruby **3.4.11**, PostgreSQL **17**, Flutter **3.47** (stable),
> JDK **17**, Gradle 9.3 (tự tải).

| Phần | Bắt buộc? | Thời gian (ước tính) |
|------|-----------|----------------------|
| [0. Mang bí mật từ máy cũ](#0-những-thứ-không-có-trên-github) | Tuỳ phần dùng | 10 phút |
| [A. Web Rails](#a-web-rails) | Có | 30–45 phút |
| [B. Trang thử nghiệm qua tunnel](#b-trang-thử-nghiệm-qua-tunnel) | Khi cần cho điện thoại / người khác thử | 15 phút |
| [C. App Android](#c-app-android-windows) | Khi làm app | 45–60 phút |

---

## 0. Những thứ không có trên GitHub

Repo **công khai**, nên mọi bí mật nằm **ngoài repo** (`CLAUDE.md`, BM-04). Trước khi bỏ máy cũ, chép các file dưới đây sang
máy mới qua **USB hoặc trình quản lý mật khẩu**. **Không bao giờ** commit, gửi qua chat/email hay dán vào issue.

| Ở máy cũ | Đặt ở máy mới | Dùng cho | Thiếu thì sao |
|----------|---------------|----------|---------------|
| `~/projects/vn_badminton/config/master.key` | cùng chỗ, `chmod 600` | Giải mã `config/credentials.yml.enc` (SMTP, người gửi email, khoá bí mật của chế độ production) | **Dev vẫn chạy**; tunnel (production) và gửi email thật thì không. Mất hẳn → phải tạo credentials mới và nhập lại SMTP |
| `~/.config/vn_badminton/sepay_webhook_api_key` | cùng chỗ, `chmod 600` | Khoá webhook SePay (xác nhận chuyển khoản, TT-04) | Giao dịch ngân hàng không về; lấy lại khoá trong trang quản trị SePay |
| `~/.config/vn_badminton/firebase-service-account.json` | cùng chỗ, `chmod 600` | Gửi thông báo đẩy (TB-04) | Không gửi thông báo đẩy; tạo khoá mới trong Firebase Console → Project settings → Service accounts |
| `D:\dev\vn_badminton_mobile\android\app\google-services.json` | cùng chỗ | App nhận thông báo đẩy | Tải lại trong Firebase Console ([`firebase.md`](https://github.com/itssamuelnguyen-vn/vn_badminton_mobile/blob/main/docs/firebase.md)) |
| `%USERPROFILE%\.android\debug.keystore` (Windows) | cùng chỗ | Khoá ký APK debug: **đăng nhập Google trong app** và **link mở thẳng app** dựa vào vân tay khoá này | Máy mới tạo khoá khác → phải thêm SHA-1 mới vào Google Cloud và đổi `ANDROID_CERT_SHA256` (mục C5) |
| `~/.config/vn_badminton/postgres_password`, `backup.env` | cùng chỗ, `chmod 600` | Chỉ cho việc **triển khai lên server** (nhánh `deploy-config`) | Không ảnh hưởng việc phát triển |

Các giá trị **không bí mật** nhưng cần biết: `GOOGLE_WEB_CLIENT_ID` (Google Cloud Console → APIs & Services → Credentials →
Web client), `ANDROID_CERT_SHA256` (tính từ `debug.keystore`, mục C5).

```bash
# Máy mới, sau khi chép: thư mục chỉ mình bạn đọc được.
mkdir -p ~/.config/vn_badminton && chmod 700 ~/.config/vn_badminton
chmod 600 ~/.config/vn_badminton/* ~/projects/vn_badminton/config/master.key
```

---

## A. Web Rails

### A1. Hệ điều hành
- **Windows**: dùng **WSL2 + Ubuntu 24.04** (như máy hiện tại). PowerShell (quyền admin):
  ```powershell
  wsl --install -d Ubuntu-24.04
  ```
  Khởi động lại, mở **Ubuntu**, tạo user. Mọi lệnh phần A và B chạy **trong Ubuntu**. Để code trong `~/projects`
  (ổ của WSL), **không** để ở `/mnt/c` hay `/mnt/d` (chậm hơn nhiều lần).
- **macOS / Linux**: chạy trực tiếp; thay `apt` bằng Homebrew (`brew install postgresql@17 libpq libyaml vips`) khi cần.

### A2. Gói hệ thống
```bash
sudo apt update
sudo apt install -y build-essential git curl unzip libpq-dev libyaml-dev libffi-dev zlib1g-dev libssl-dev libvips
```
`libvips` để xử lý ảnh đại diện (thiếu thì chỉ có cảnh báo khi chạy).

### A3. PostgreSQL 17
```bash
sudo apt install -y postgresql-common
sudo /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh   # thêm kho PGDG, bấm Enter
sudo apt install -y postgresql-17
sudo service postgresql start                                    # WSL không tự chạy dịch vụ
sudo -u postgres createuser --superuser "$(whoami)"              # Rails kết nối bằng user Linux, không mật khẩu
```
WSL: mỗi lần mở máy chạy lại `sudo service postgresql start` (hoặc bật systemd trong `/etc/wsl.conf`: `[boot]` `systemd=true`).

### A4. Ruby 3.4.11 (qua mise)
```bash
curl https://mise.run | sh
echo 'eval "$(~/.local/bin/mise activate bash)"' >> ~/.bashrc && source ~/.bashrc
```
Ruby được cài ở bước A6 (repo có `mise.toml` và `.ruby-version`).

### A5. Kết nối GitHub và lấy code
```bash
ssh-keygen -t ed25519 -C "email-github-cua-ban"     # Enter cho mặc định
cat ~/.ssh/id_ed25519.pub                            # dán vào GitHub → Settings → SSH and GPG keys → New SSH key
ssh -T git@github.com                                # "Hi itssamuelnguyen-vn!"
git config --global user.name "Samuel Cruz"
git config --global user.email "email-github-cua-ban"

mkdir -p ~/projects && cd ~/projects
git clone git@github.com:itssamuelnguyen-vn/vn_badminton.git
cd vn_badminton
```
Tuỳ chọn: cài GitHub CLI (`sudo apt install gh`, rồi `gh auth login`) để xem PR/CI từ terminal.

### A6. Cài thư viện, tạo database
```bash
cd ~/projects/vn_badminton
mise trust && mise install ruby@3.4.11   # Ruby đúng phiên bản của repo
gem install bundler
cp /đường-dẫn-đã-chép/master.key config/master.key && chmod 600 config/master.key   # mục 0, tuỳ chọn cho dev
bin/setup --skip-server                  # bundle install + tạo 3 database dev + nạp dữ liệu mẫu (db/seeds.rb)
```
`db/seeds.rb` tạo **cơ sở, 10 sân, giờ mở cửa, bảng giá mẫu**. Tạo **tài khoản chủ sân**:
```bash
ADMIN_EMAIL=ban@example.com ADMIN_PASSWORD='mat-khau-dai' ADMIN_NAME='Tên chủ sân' bin/rails db:seed
```

### A7. Chạy
```bash
bin/dev        # web (localhost:3000) + Tailwind tự build lại + job nền (bin/jobs)
```
Mở <http://localhost:3000>. Email ở dev **không gửi thật**: mở bằng letter_opener (file trong `tmp/letter_opener/`).
Gửi email thật qua SMTP trong credentials: `SMTP=1 bin/dev` (cần `master.key`).

Biến môi trường tuỳ chọn cho dev (thêm vào `~/.bashrc` khi cần thử tính năng đó):
```bash
export GOOGLE_WEB_CLIENT_ID=...apps.googleusercontent.com                     # nút "Tiếp tục với Google" (AP-05)
export FIREBASE_SERVICE_ACCOUNT_PATH=$HOME/.config/vn_badminton/firebase-service-account.json   # thông báo đẩy
export SEPAY_WEBHOOK_API_KEY=$(cat ~/.config/vn_badminton/sepay_webhook_api_key)              # webhook SePay
```

### A8. Kiểm tra trước khi commit
```bash
bin/rails test && bin/rubocop && bin/brakeman -q && bin/bundler-audit
```
**Test giao diện** (`bin/rails test:system`, chạy trình duyệt thật) cần **Google Chrome** trong Ubuntu:
```bash
wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
sudo apt install -y ./google-chrome-stable_current_amd64.deb
```
CI trên GitHub chạy đủ cả các bước này khi push.

---

## B. Trang thử nghiệm qua tunnel

Chạy web ở **chế độ production trên máy mình** với database riêng, mở ra Internet qua **Cloudflare quick tunnel**
(`https://<ngẫu-nhiên>.trycloudflare.com`, không cần tài khoản) để thử trên điện thoại, cho SePay gọi webhook, và cho app
kết nối. Script nằm trong repo: [`script/tunnel/`](../script/tunnel/). Cần `config/master.key` (mục 0).

### B1. Cài cloudflared
```bash
curl -L -o /tmp/cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
sudo apt install -y /tmp/cloudflared.deb
cloudflared --version
```

### B2. Cấu hình (một lần)
```bash
mkdir -p ~/.local/share/vn_badminton/tunnel && chmod 700 ~/.local/share/vn_badminton/tunnel
cp ~/projects/vn_badminton/script/tunnel/env.example.sh ~/.local/share/vn_badminton/tunnel/env.sh
nano ~/.local/share/vn_badminton/tunnel/env.sh      # bỏ dấu # ở GOOGLE_WEB_CLIENT_ID, ANDROID_CERT_SHA256 nếu dùng
echo "alias start-tunnel='~/projects/vn_badminton/script/tunnel/restart.sh'" >> ~/.bash_aliases && source ~/.bash_aliases
```
`env.sh` **không** chứa bí mật: nó đọc khoá SePay và Firebase từ `~/.config/vn_badminton/` (mục 0).

### B3. Chạy
```bash
start-tunnel
```
Lần đầu tạo 4 database `vn_badminton_tunnel*` (trống) và build CSS/JS; in ra **Public URL**. Tạo tài khoản chủ sân cho
database này:
```bash
cd ~/projects/vn_badminton
(source ~/.local/share/vn_badminton/tunnel/env.sh; ADMIN_EMAIL=... ADMIN_PASSWORD=... bin/rails db:seed)
```

- **Sau mỗi lần sửa code** (giữ nguyên URL):
  ```bash
  (source ~/.local/share/vn_badminton/tunnel/env.sh; cd ~/projects/vn_badminton; bin/rails db:migrate && bin/rails assets:precompile && bin/rails restart)
  ```
  **Không** chạy `assets:clobber` khi server đang chạy (trang đang mở mất CSS).
- **Mỗi lần `start-tunnel` URL đổi**; khi đó cập nhật:
  - **SePay** → Webhook: `<URL>/webhooks/sepay`;
  - **Google Cloud** → Web client → *Authorized JavaScript origins*: thêm `<URL>` (đăng nhập Google trên web);
  - **App**: `start-tunnel` tự ghi URL vào `config/dev.json` của app (đường dẫn `MOBILE` trong `env.sh`), rồi **build lại APK**.
- Log: `~/.local/share/vn_badminton/tunnel/server.log`. Chrome có thể cảnh báo "Dangerous" với `trycloudflare.com`
  (do cả tên miền dùng chung), không phải lỗi của app.

---

## C. App Android (Windows)

Phần này chạy **trên Windows** (không trong WSL): Flutter trong WSL lỗi vì script có ký tự xuống dòng kiểu Windows.

### C1. Cài công cụ
1. **Git for Windows** (<https://git-scm.com>) và **VS Code** + tiện ích **Flutter** (kèm Dart).
2. **Android Studio** (<https://developer.android.com/studio>): mở **More Actions → SDK Manager**, cài
   *Android SDK Platform* mới nhất, *Android SDK Command-line Tools*, *Android SDK Platform-Tools*.
   Android Studio có sẵn **JDK 17** (app cần JDK 17).
3. **Flutter SDK** (kênh stable, 3.47 trở lên): giải nén vào `D:\dev\flutter`, thêm `D:\dev\flutter\bin` vào biến
   **Path** của Windows. Mở PowerShell mới:
   ```powershell
   flutter doctor --android-licenses     # chấp nhận hết (y)
   flutter doctor                        # Android toolchain và VS Code phải có dấu ✓
   ```

### C2. Lấy code
```powershell
cd D:\dev
git clone https://github.com/itssamuelnguyen-vn/vn_badminton_mobile.git
cd vn_badminton_mobile
flutter pub get
```

### C3. Cấu hình
- `config\dev.json` (không commit): chép từ `config\dev.example.json`, đặt `API_URL` là URL tunnel (mục B3), **không** có `/` cuối.
- `android\app\google-services.json` và `%USERPROFILE%\.android\debug.keystore`: chép từ máy cũ (mục 0).

### C4. Chạy và build
- Điện thoại: bật **Tuỳ chọn nhà phát triển → Gỡ lỗi USB**, cắm cáp, chấp nhận máy tính. Trong VS Code mở **thư mục**
  `D:\dev\vn_badminton_mobile`, nhấn **F5**.
- Build APK để gửi: **Ctrl+Shift+B** → `build\apk\vnbadminton-<phiên bản>-<ngày giờ>.apk`
  (chi tiết: [`build-apk.md`](https://github.com/itssamuelnguyen-vn/vn_badminton_mobile/blob/main/docs/build-apk.md)).
- Kiểm tra trước khi commit: `flutter analyze` và `flutter test`.

### C5. Khi máy mới dùng khoá debug khác
Nếu không mang được `debug.keystore` từ máy cũ, Android Studio tạo khoá mới khi build lần đầu. Khi đó:
```powershell
keytool -list -v -keystore "$env:USERPROFILE\.android\debug.keystore" -alias androiddebugkey -storepass android -keypass android
```
- Dòng **SHA1** → Google Cloud → Credentials → thêm (hoặc sửa) **OAuth client loại Android** cho gói
  `com.vnbadminton.vn_badminton_mobile` (thiếu → đăng nhập Google trong app báo lỗi).
- Dòng **SHA256** → `ANDROID_CERT_SHA256` trong `env.sh` của tunnel (link mở thẳng app, AP-04), rồi khởi động lại server.

---

## Kiểm tra cuối

- [ ] <http://localhost:3000> mở được; đăng nhập bằng tài khoản chủ sân; **Quản lý** hiện đủ 4 nhóm.
- [ ] `bin/rails test` xanh.
- [ ] `start-tunnel` in ra URL; `<URL>/up` trả về trang xanh trên điện thoại.
- [ ] App chạy trên điện thoại, đăng ký/đăng nhập được với server tunnel.
- [ ] (Nếu dùng) chuyển khoản thử nhỏ → SePay gọi webhook → lượt đặt tự xác nhận.

## Ghi chú
- **Docker**: repo có `Dockerfile` cho **production** (Kamal, nhánh `deploy-config`), chưa có môi trường phát triển bằng
  Docker / Dev Container. Khi cần, có thể thêm `.devcontainer/` (Ruby + PostgreSQL + Chrome) để rút phần A còn vài phút.
- Tài liệu liên quan: [`business-rules.md`](business-rules.md), [`business-processes.md`](business-processes.md), [`api.md`](api.md).
