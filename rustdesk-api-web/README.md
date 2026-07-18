# RustDesk API Web

A web administration panel based on Vue 3 and Element Plus, tailored for RustDesk self-hosted servers.

This project is a custom fork of the upstream repository: [https://github.com/lejianwen/rustdesk-api-web](https://github.com/lejianwen/rustdesk-api-web).

---

## Key Modifications / Các thay đổi chính

Compared to the upstream version, this fork includes the following enhancements and features:

### 1. Localization / Bản dịch
- Removed Chinese interface elements and translated the administration panel into English and Vietnamese (Viet hóa).

### 2. Client Deployment & Auto-Configuration / Triển khai & Cấu hình Client tự động
- Added **My -> Client Config** page to view client configurations.
- Added a generator for self-downloading PowerShell deployment commands for Windows client setup.
- Enabled direct downloading of deployment script templates.

### 3. Remote Password Management / Quản lý mật khẩu từ xa
- Implemented remote password viewing and management in the address book and peer views.
- Introduced options for structured (randomly generated) and custom passwords.

### 4. Deploy Token Management / Quản lý Token triển khai
- Added features to list, generate, and revoke short-lived deployment tokens.

---

## Installation & Development / Hướng dẫn Cài đặt & Phát triển

This directory is integrated into the monorepo. You can build and run it locally, or deploy it using the main Docker Compose stack.

### Local Development / Phát triển cục bộ
To run this application locally for development:
```shell
# Navigate to this directory from the repository root
cd rustdesk-api-web

# Install dependencies
npm install

# Start development server
npm run dev
```

### Production Build / Đóng gói sản xuất
```shell
# Compile and build the application
cd rustdesk-api-web
npm run build
```

The build output will be generated in the `dist` folder, which is served by Nginx or the Go API in the Docker Compose stack.

