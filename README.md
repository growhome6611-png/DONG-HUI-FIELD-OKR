# DONG HUI FIELD KPI | 现场工程师日报与绩效管理

Web App/PWA dùng trên điện thoại Android, iPhone và máy tính. Deploy trên **Vercel**.

## Tính năng bản v1.0
- Đăng nhập email/mật khẩu, phân quyền: **Kỹ sư / Chỉ huy trưởng / Giám đốc hạng mục / Quản trị**.
- Kỹ sư: báo cáo quân số, vật tư, thiết bị, mặt bằng, kế hoạch đầu ca; kết quả, nghiệm thu, vướng mắc, kế hoạch cuối ngày.
- Checklist 13 công việc chia 3 giai đoạn; lưu riêng theo kỹ sư và ngày.
- Sổ lỗi chất lượng: nhà thầu, vị trí, nội dung, mức độ, ảnh, hạn xử lý, kết quả, trạng thái. Chỉ cấp quản lý xác nhận đóng lỗi trên môi trường thật.
- Chỉ huy trưởng: xem báo cáo và chấm **25 tiêu chí, 6 nhóm trọng số 15/25/25/15/10/10 = 100 điểm** cho kỹ sư công trình mình.
- Giám đốc hạng mục: xem dữ liệu và chấm KPI nhiều công trình.
- Quản trị: tạo công trình, phân quyền và gán công trình cho người dùng.
- Xem lịch sử đánh giá, xuất CSV mở bằng Excel (UTF-8), giao diện thích ứng điện thoại, cài PWA.
- Nếu chưa có Supabase, app chạy **chế độ demo cục bộ** để trải nghiệm (không đồng bộ, không dùng cho dữ liệu thật).

## Bước 1. Tạo cơ sở dữ liệu Supabase
1. Vào https://supabase.com, tạo Project mới, lưu mật khẩu database an toàn.
2. Vào **SQL Editor**, dán toàn bộ nội dung `supabase_setup.sql` và Run.
3. Trong **Authentication > Providers > Email**, bật Email. Để sử dụng thật nên **bật xác minh email**.
4. Trong **Project Settings / Data API**, lấy Project URL và **Publishable key / anon public key**. Tuyệt đối **không** dùng `service_role` key.
5. Sửa tệp `config.js`:
   ```js
   window.DONGHUI_CONFIG = {
     supabaseUrl: 'https://TEN_DU_AN.supabase.co',
     supabaseAnonKey: 'sb_publishable_...'
   };
   ```
6. Đăng ký tài khoản quản trị đầu tiên trong app (phải xác minh email nếu bắt buộc). Vào SQL Editor chạy:
   ```sql
   update public.profiles set role='admin'
   where email='email-quan-tri-cua-ban@congty.com';
   ```
7. Đăng xuất/đăng nhập lại. Vào **Quản trị**, tạo công trình và gán người dùng vào vai trò, công trình. Người dùng mới mặc định là kỹ sư không có dự án, không tự đổi thành quản lý.

**Lưu ý:** Khi tạo công trình, quản trị cần đăng ký trước bằng email giống các thành viên khác. App không tự tạo user khác bằng email (tránh phải đưa quyền quản trị Supabase ra trình duyệt).

## Bước 2. Đưa lên GitHub và triển khai Vercel
1. Giải nén ZIP, đưa toàn bộ các file nằm **trong** thư mục này lên root của một GitHub repository (gồm `index.html`, `app.js`, `style.css`, `config.js`, `vercel.json`, `manifest.webmanifest`, `icon.svg`).
2. Vào https://vercel.com/new -> Import Git repository.
3. Framework Preset: **Other**. Root Directory: `./`. Không cần Build Command; không cần Output Directory.
4. Deploy. Mở URL `https://...vercel.app`.
5. Supabase **Authentication > URL Configuration**: đặt Site URL là địa chỉ Vercel, thêm Redirect URLs cần thiết (ví dụ `https://ten-app.vercel.app/**`).
6. Đăng nhập thử trên điện thoại và PC bằng **cùng tài khoản** để kiểm tra dữ liệu đồng bộ.

**Cách cài vào điện thoại**: Android Chrome > menu 3 chấm > Cài đặt ứng dụng/Thêm vào màn hình chính. iPhone Safari > Chia sẻ > Thêm vào Màn hình chính.

## Bảo mật & phân quyền
- Tất cả bảng lưu dữ liệu được bật Row Level Security (RLS) trong `supabase_setup.sql`.
- Kỹ sư sửa báo cáo của mình, không được tự chấm KPI; không được tự xác nhận đóng lỗi trên DB.
- Chỉ huy trưởng chỉ đọc/chấm trong công trình được phân công; giám đốc hạng mục quản lý tất cả công trình.
- Ảnh lỗi ở bucket riêng tư, truy cập qua đường dẫn ký ngắn hạn.
- Cấu hình `config.js` chứa **public anon key**, không chứa khóa bí mật; truy cập dữ liệu phải qua RLS.
- Ứng dụng có giới hạn 1 báo cáo / kỹ sư / ngày và 1 phiếu KPI / kỹ sư / ngày.

## Lưu ý trước khi phát hành chính thức
- Nên thử nghiệm nội bộ, xác nhận quy trình ký xác nhận và quyền hạn các cấp.
- KPI hiện là bộ tiêu chí dự thảo, cần quy chế phê duyệt; không tự động áp dụng thưởng phạt.
- Bản này chưa có chức năng: duyệt báo cáo nhiều cấp, thông báo push, chữ ký điện tử, xuất PDF, tích hợp trực tiếp Sitecam/Drive, bản dịch Trung-Việt ở **mọi trường dữ liệu**.
- CSV hỗ trợ Excel; có thể phát triển thêm Excel đa-sheet sau.
- Cần đặt tên người dùng, công trình chính xác và bật xác thực email trước triển khai thật.
- Demo lưu localStorage của trình duyệt; muốn reset demo hãy xóa site data của trình duyệt.

## Danh mục file
- `index.html` – điểm vào PWA.
- `app.js` – giao diện, nghiệp vụ, quyền thao tác.
- `style.css` – giao diện responsive.
- `config.js` – URL + public key Supabase.
- `supabase_setup.sql` – bảng dữ liệu, kiểm soát quyền, kho ảnh.
- `vercel.json` – cấu hình Vercel.
- `manifest.webmanifest`, `icon.svg` – PWA.

© Dong Hui. Bản nền tảng để phát triển tiếp.
