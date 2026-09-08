# Phương án duy trì remote cho các máy đã cài

Ngày khảo sát: 2026-09-08. Phạm vi: `D:/projects/RustDesk` (project server/API cũ) và `D:/projects/rustdeskclient` (source client hiện tại). Đây là đề xuất dựa trên source/config local, chưa phải xác nhận trạng thái production hoặc các binary đang cài.

## Quyết định đề xuất

Giữ fork Rust `hbbs/hbbr` và API Go hiện có; ưu tiên tương thích với máy đã cài. Luồng remote theo ID phải tiếp tục hoạt động khi API bảo trì, trong chế độ không bắt buộc đăng nhập. API đảm nhiệm tài khoản, danh bạ, inventory, deploy và audit. Không thêm bước gọi API đồng bộ vào mỗi lần đăng ký ID hoặc thiết lập kết nối trong giai đoạn này.

```text
Client A/B --> hbbs:21116 TCP/UDP --> tìm ID, thương lượng kết nối
Client A <-----------------------> Client B: direct khi khả dụng
Client A <---- hbbr:21117 TCP ----> Client B: relay khi cần
Client A/B --> HTTPS API --> tài khoản, danh bạ, inventory, audit
```

Mục tiêu tương thích là các máy được phép truy cập tiếp tục remote hai chiều bằng ID hiện có; quyền chấp nhận/mật khẩu tại máy đích vẫn áp dụng. Có tên trong danh bạ không đồng nghĩa được phép điều khiển máy đích.

## Kết quả index và đối chiếu

- `D-projects-RustDesk`: 14.990 nodes, 74.908 edges, moderate index.
- `D-projects-rustdeskclient`: 15.476 nodes, 71.044 edges, moderate index.
- Cross-repo intelligence trả về 0 cross edges; các URL được ghép động và giao thức protobuf cần đối chiếu trực tiếp, không thể suy ra không có phụ thuộc từ kết quả này.
- Client khai báo `1.5.0`, HEAD `e5d473407`. Gitlink `libs/hbb_common` yêu cầu `55395c6fcbcb8dd4bc8d4e7ab4d7d7c8d1789b43`; file proto của submodule đang thiếu ở checkout local.
- Server khai báo `1.1.15`; SHA256 proto server là `1A79E328400D8D7D99D42A4DD562BA062EDC301DEDBEE3467007A7F7E844E7A9`. Số version client/server không cần bằng nhau, nhưng wire contract phải tương thích.
- `task.md` mô tả client `1.4.7` và submodule cũ, nên kết quả hash/test được ghi ở đó không chứng minh tương thích với client hiện tại.
- Các route `/api/devices/deploy`, `/api/devices/cli`, audit active/note/alarm đã tồn tại trong `rustdesk-api/http/router/api.go:14`. Ghi chú cũ rằng chưa có deploy route đã lỗi thời.
- `rustdesk-server/src/rendezvous_server.rs:887`: `MUST_LOGIN` kiểm tra JWT của bên yêu cầu tại `PunchHoleRequest`; không phải cơ chế bắt buộc mọi máy đích phải deploy. Không coi deploy API là một ACL cho luồng remote.
- `rustdesk-api/http/controller/api/index.go:47`: heartbeat trả `{}`, cập nhật last-online theo ID; chỉ kiểm tra UUID không rỗng, chưa so UUID với bản ghi. Route heartbeat nằm ngoài middleware đăng nhập.
- `rustdeskclient/src/hbbs_http/sync.rs:87`: client gửi heartbeat/sysinfo không kèm bearer ở các lời gọi này; xử lý `strategy` và `disconnect` khi API trả về. Không thể thêm yêu cầu user JWT vào heartbeat cũ mà mặc định vẫn tương thích.
- `rustdeskclient/src/common.rs:1119`: khi thiếu API URL tường minh, client có thể suy ra `http://<ID-server>:21114`. Vì vậy cần kiểm kê trước khi đóng port này.
- `rustdeskclient/src/common.rs:1935`: key có thể đến từ tên executable Windows, cấu hình hoặc giá trị mặc định. Source hiện tại không chứng minh cấu hình của các binary đã cài.

## Những thứ phải bảo toàn

| Thành phần | Cách xử lý |
|---|---|
| ID/relay endpoint | Giữ hostname và port mà máy cũ dùng. `.env` local là `rd.ngoctuct.io.vn`; xác minh thực tế trước cutover. Máy dùng IP cố định cần giữ IP, forwarding hoặc cập nhật cấu hình có kiểm soát. |
| API endpoint | Giữ `rustdesk.ngoctuct.io.vn` và các path/response cũ. Duy trì endpoint API suy ra ở port 21114 nếu còn client sử dụng. |
| Server identity | Sao lưu và khôi phục cả `id_ed25519` và `id_ed25519.pub`; xác minh public-key fingerprint trước mở traffic. Không sinh key mới khi chuyển host. |
| Server DB | Giữ `data/server`, đặc biệt dữ liệu peer ID/public key. Backup SQLite nhất quán, có xét WAL; không copy riêng file DB đang ghi. |
| API DB và JWT | Giữ `data/api`, user/device/address-book và JWT secret đang dùng; không đổi secret cùng lần chuyển host. |
| Máy đã cài | Giữ device ID, keypair, mật khẩu unattended và cấu hình service/user. Không chạy lại deploy hàng loạt nếu script có thể đặt lại mật khẩu hoặc owner. |

Nếu còn quyền quản lý domain/IP cũ và keypair cũ, chuyển backend có thể không cần cài lại client. Nếu mất endpoint hoặc private key cũ, chưa thể cam kết phương án server-only đáp ứng toàn bộ máy đã cài.

## Tối ưu server và triển khai

1. Giữ một `hbbs` active và một `hbbr` ban đầu. Direct ưu tiên, relay dự phòng; không ép relay toàn bộ nếu chưa có nhu cầu mạng cụ thể. Chưa thêm Redis/Kubernetes hoặc nhiều hbbs active vì chưa có số liệu tải và cơ chế chia sẻ trạng thái peer được kiểm chứng.
2. Giữ chính sách đăng nhập hiện hữu khi chuyển đổi. Compose mặc định `MUST_LOGIN=N`, `.env` local không khai báo biến này; chưa xác minh môi trường/runtime production. Với mục tiêu remote theo ID không phụ thuộc tài khoản API, chọn `N` sau khi xác nhận chính sách vận hành. Nếu production đang `Y`, phải đánh giá riêng tác động quyền truy cập trước đổi.
3. Chưa bật deploy-required cho máy cũ. Nếu cần quản lý chặt về sau, nhập danh sách máy hiện hữu từ dữ liệu đáng tin, hỗ trợ nhận diện bằng key thiết bị, rồi áp dụng cho máy mới theo đợt.
4. Compose hiện cho API và hbbr dùng `network_mode: service:hbbs`, API điều khiển server qua `127.0.0.1`. Giai đoạn đầu giữ topology đã chạy; kế tiếp tách network namespace để recreate hbbs không kéo theo phụ thuộc namespace. Trước tách phải rà command/control listener đang chỉ nghe loopback; không chỉ sửa host thành service name rồi mở control port công khai.
5. API chỉ cần public HTTPS qua proxy, các cổng native cần public TCP 21115/21116/21117 và UDP 21116 theo nhu cầu client. WebSocket 21118/21119 nên chỉ nhận từ proxy khi dùng web client. Port 21114 chỉ thu hẹp sau kiểm kê endpoint API cũ.
6. Đặt healthcheck riêng từng dịch vụ và smoke probe giao thức từ ngoài host. Giám sát số peer đăng ký, đăng ký lỗi, tỷ lệ direct/relay, lỗi handshake/key/token, relay bandwidth, RSS/OOM và API latency. HTTP 200 không chứng minh remote hoạt động.
7. Hai limit 64 MB trong Compose cần đánh giá bằng đo tải; không đủ cơ sở coi đây là mức tối ưu. Chọn giới hạn có dư địa từ RSS thực tế và thử số phiên relay đồng thời dự kiến. Dung lượng đường truyền dựa trên số phiên đồng thời, không chỉ số máy đăng ký.
8. Pin image theo release/commit hoặc digest, lưu image trước nâng cấp để rollback. Có máy dự phòng và quy trình khôi phục đã thử; chỉ một hbbs active khi chưa có thiết kế đồng bộ trạng thái. Không dùng DNS round-robin hai hbbs độc lập như giải pháp HA.

## Phạm vi API ưu tiên

| Ưu tiên | Công việc | Lợi ích cho máy cũ |
|---|---|---|
| P0 | Giữ login/currentUser, address book, peers, deploy/cli và schema response hiện có; test bằng payload của các client thực tế | Không mất danh bạ/đăng nhập sau nâng cấp |
| P0 | Giữ lỗi/bảo trì API không chặn đăng ký ID và remote theo ID trong chế độ không bắt buộc login | Có thể nhập ID đã biết để hỗ trợ khi API lỗi |
| P1 | Phân biệt `last_api_seen` và trạng thái đăng ký hbbs trong mô hình/UI; bổ sung đọc trạng thái nội bộ có xác thực nếu cần | Tránh coi heartbeat API là bằng chứng remote được |
| P1 | Với heartbeat legacy: ít nhất so UUID với thiết bị đã biết, giới hạn tốc độ và không dùng heartbeat để đổi owner/key/quyền | Giảm ghi sai inventory; UUID không được coi là bí mật hay bằng chứng mật mã |
| P1 | Thêm danh tính thiết bị có xác thực cho client hỗ trợ, chạy song song contract legacy | Có đường nâng cấp bảo mật mà không khóa máy cũ |
| P1 | Giữ backup DB nhất quán, migration additive và kiểm tra quyền sở hữu deploy/CLI | Giữ device/user mapping và khả năng rollback |
| P2 | Policy/strategy/disconnect chỉ triển khai sau khi xác thực thiết bị và kiểm thử từng version | Tránh đẩy nhầm cấu hình hoặc ngắt remote đang dùng |

Chưa ưu tiên recording upload, plugin signing hay mở rộng web client để đạt mục tiêu remote giữa máy đã cài. Xóa/disable một thiết bị trong API hiện không được mặc định hiểu là đã thu hồi quyền kết nối ở hbbs. JWT stateless cũng không tự phản ánh logout/revoke trong API.

## Thứ tự thực hiện và nghiệm thu

1. Lấy mẫu máy đang cài: version, ID/relay/API endpoint, fingerprint public key, kiểu cài service/portable, trạng thái login; không thu mật khẩu. Phân nhóm máy dùng domain/IP và API explicit/inferred. Xác nhận host production thực sự tương ứng với config local.
2. Khôi phục submodule client đúng gitlink trong môi trường được phép; so sánh protobuf theo field number/type/enum với server. Khóa commit của từng component và xây matrix cho client đang dùng, không chỉ HEAD mới nhất.
3. Dựng staging với bản sao dữ liệu/key được bảo vệ và endpoint thử nghiệm. Chạy API contract tests, protocol tests và hai client thật. Không dùng lại kết quả test lịch sử làm nghiệm thu lần này.
4. Chạy ma trận: máy cũ ↔ cũ, cũ ↔ 1.5.0; cùng LAN, khác NAT, CGNAT, UDP bị chặn, direct TCP/UDP, IPv6 nếu dùng, force relay, WebSocket nếu dùng; cả hai chiều. Reboot máy đích và thử unattended trước khi người dùng đăng nhập Windows.
5. Thử dừng API: phiên đang chạy và mở phiên mới theo ID đã biết phải hoạt động trong chế độ không bắt buộc login; danh bạ/login có thể tạm không dùng được. Thử restart hbbs và hbbr riêng, ghi thời gian máy đăng ký/kết nối lại; restart relay có thể ngắt phiên relay đang chạy.
6. Sao lưu nhất quán, xác minh key, chuẩn bị image/DB rollback rồi chuyển endpoint cũ sang host mới trong cửa sổ bảo trì. Giữ host cũ để rollback nhưng tránh hai nguồn ghi DB tách rời. Nếu DB schema mới không backward-compatible, rollback bằng snapshot phù hợp và chấp nhận phần dữ liệu sau snapshot cần xử lý riêng.
7. Chỉ nghiệm thu khi ID/key/mật khẩu máy mẫu không đổi, kết nối hai chiều thành công, relay hoạt động khi direct thất bại, endpoint cũ còn phục vụ và rollback đã diễn tập. Sau ổn định mới tách namespace hoặc nâng bảo mật theo đợt.

## Giới hạn khảo sát

Chưa build/test runtime lần này; thiếu proto submodule client nên chưa xác nhận tương thích wire đầy đủ với 1.5.0. Chưa truy cập máy đã cài, đo tải, kiểm tra DNS/firewall production hay xác nhận keypair production. Không thay đổi code runtime, cấu hình triển khai hoặc dữ liệu máy đang chạy trong khảo sát này.

Tham chiếu chính thức về cài đặt/cổng và cấu hình client: https://rustdesk.com/docs/en/self-host/rustdesk-server-oss/install/ và https://rustdesk.com/docs/en/self-host/client-configuration/. Các quyết định dành cho fork này dựa trên source local được nêu ở trên.
