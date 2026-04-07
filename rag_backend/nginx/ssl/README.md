이 디렉토리에 SSL 인증서 파일을 배치하세요:

- fullchain.pem  : SSL 인증서 (전체 체인)
- privkey.pem    : 개인 키

Let's Encrypt를 사용하는 경우:
  certbot certonly --standalone -d your-domain.com
  cp /etc/letsencrypt/live/your-domain.com/fullchain.pem ./
  cp /etc/letsencrypt/live/your-domain.com/privkey.pem ./
