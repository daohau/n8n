# Install
```bash
curl -sSL https://raw.githubusercontent.com/daohau/n8n/refs/heads/main/install_n8n_nocodb_v3.sh > install_n8n_nocodb_v3.sh && chmod +x install_n8n_nocodb_v3.sh && sudo ./install_n8n_nocodb_v3.sh
```

# Menu quản lý
```bash
sudo ./install_n8n_nocodb_v3.sh manage
```

# Đăng ký lại SSL
```bash
sudo certbot --nginx -d noco.modaviet.pro.vn --non-interactive --agree-tos --email your-email@example.com --redirect
```
