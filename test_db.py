import os
from dotenv import load_dotenv
from sqlalchemy import create_engine, text

# 실행 확인용 (이게 터미널에 먼저 떠야 합니다)
print("\n🚀 [1단계] 테스트 스크립트를 시작합니다!")

# 1. .env 로드
load_dotenv()
db_url = os.getenv("DATABASE_URL")

print(f"🚀 [2단계] .env에서 불러온 주소 확인: {db_url}")

if not db_url:
    print("❌ 에러: .env 파일에 DATABASE_URL이 없거나 파일 위치가 잘못되었습니다.")
else:
    try:
        print("🚀 [3단계] DB 연결 시도 중... (잠시만 기다려주세요)")
        engine = create_engine(db_url)
        with engine.connect() as conn:
            result = conn.execute(text("SELECT version();"))
            print(f"\n✅ [최종] 연결 성공!!")
            print(f"서버 버전: {result.fetchone()[0]}")
    except Exception as e:
        print(f"\n❌ [에러 발생]: {e}")

print("\n🚀 [4단계] 테스트 종료.")