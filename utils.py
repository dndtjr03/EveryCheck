"""보안/비즈니스 로직 유틸리티 모음.

- 파일 SHA-256 해시 계산
- 국토부 가이드라인(벽지/장판 내구연수 10년 기준)에 따른 감가상각 계산
- AWS S3 이미지 업로드 헬퍼
"""

import hashlib
import os
import uuid
from datetime import date
from typing import Optional, Tuple

import boto3
import magic
from fastapi import UploadFile


# 전역 S3 클라이언트 (필요 시 리전/엔드포인트를 환경 변수로 조정)
_s3_client = boto3.client("s3", region_name=os.getenv("AWS_REGION", "ap-northeast-2"))

MAX_IMAGE_SIZE_BYTES = 10 * 1024 * 1024  # 10MB 제한
ALLOWED_IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp"}
ALLOWED_IMAGE_MIME_TYPES = {"image/jpeg", "image/png", "image/webp"}


async def calculate_file_sha256(upload_file: UploadFile) -> str:
    """업로드된 파일 스트림을 읽어 SHA-256 해시값(16진 문자열)을 계산한다.

    - 보안/무결성 검증을 위해 DB에 함께 저장한다.
    - 파일 포인터를 끝까지 읽은 뒤 다시 처음(0)으로 되돌린다.
    """

    sha256 = hashlib.sha256()

    # 큰 파일도 처리할 수 있도록 청크 단위로 읽어들인다.
    while True:
        chunk = await upload_file.read(1024 * 1024)  # 1MB 단위
        if not chunk:
            break
        sha256.update(chunk)

    # 이후 다른 로직에서 다시 파일을 읽을 수 있도록 포인터를 되돌린다.
    await upload_file.seek(0)

    return sha256.hexdigest()


def _get_extension(filename: Optional[str]) -> str:
    """파일명에서 확장자를 추출한다."""

    if not filename:
        return ""
    _, ext = os.path.splitext(filename)
    return ext.lower()


async def validate_and_read_image_file(upload_file: UploadFile) -> Tuple[bytes, str]:
    """이미지 업로드 보안 검증 후 파일 바이트를 반환한다.

    요구사항:
    - 파일 용량 10MB 제한
    - .jpg, .jpeg, .png, .webp 확장자 검증
    - python-magic을 사용하여 실제 MIME 타입 검증

    반환:
    - (file_bytes, detected_mime_type)
    """

    ext = _get_extension(upload_file.filename)
    if ext not in ALLOWED_IMAGE_EXTENSIONS:
        raise ValueError("허용되지 않은 파일 확장자입니다. (.jpg, .jpeg, .png, .webp 만 허용)")

    # 스트리밍으로 읽으며 용량 제한을 적용한다.
    buf = bytearray()
    total = 0
    while True:
        chunk = await upload_file.read(1024 * 1024)  # 1MB 단위
        if not chunk:
            break
        total += len(chunk)
        if total > MAX_IMAGE_SIZE_BYTES:
            raise ValueError("파일 용량이 10MB를 초과했습니다.")
        buf.extend(chunk)

    # 이후 로직에서 재사용 가능하도록 파일 포인터를 되돌린다.
    await upload_file.seek(0)

    if not buf:
        raise ValueError("빈 파일은 업로드할 수 없습니다.")

    # python-magic으로 실제 MIME 타입을 추출해 검증한다.
    detected_mime = magic.from_buffer(bytes(buf[:2048]), mime=True)
    if detected_mime not in ALLOWED_IMAGE_MIME_TYPES:
        raise ValueError("허용되지 않은 MIME 타입입니다. (image/jpeg, image/png, image/webp 만 허용)")

    # 클라이언트가 보낸 Content-Type도 함께 확인해 불일치/위조 가능성을 낮춘다.
    if upload_file.content_type and upload_file.content_type not in ALLOWED_IMAGE_MIME_TYPES:
        raise ValueError("요청의 Content-Type이 허용되지 않습니다.")

    return bytes(buf), detected_mime


async def calculate_sha256_from_bytes(data: bytes) -> str:
    """바이트 데이터의 SHA-256 해시를 계산한다."""

    return hashlib.sha256(data).hexdigest()


async def upload_image_to_s3(
    upload_file: UploadFile,
    bucket_name: str,
    key_prefix: str = "damage-images",
    body: Optional[bytes] = None,
    content_type: Optional[str] = None,
) -> str:
    """이미지 파일을 S3에 업로드하고 공개 URL을 반환한다.

    - key_prefix 하위에 UUID 기반 파일명을 생성한다.
    - 실제 운영 환경에서는 프리사인 URL, 권한 정책 등을 함께 고려해야 한다.
    """

    if not bucket_name:
        # 버킷 이름이 설정되지 않은 경우는 애플리케이션 설정 오류에 가깝다.
        raise ValueError("S3 버킷 이름이 설정되지 않았습니다. S3_BUCKET_NAME 환경 변수를 확인하세요.")

    original_name = upload_file.filename or "upload"
    _, ext = os.path.splitext(original_name)
    ext = ext or ".bin"

    file_id = str(uuid.uuid4())
    key = f"{key_prefix}/{file_id}{ext}"

    # 파일 내용을 메모리로 읽어 S3에 업로드한다. (호출부에서 body를 넘겨주면 재사용)
    if body is None:
        body = await upload_file.read()
        await upload_file.seek(0)

    _s3_client.put_object(
        Bucket=bucket_name,
        Key=key,
        Body=body,
        ContentType=content_type or upload_file.content_type or "application/octet-stream",
    )

    # 가장 단순한 형태의 퍼블릭 URL (버킷이 퍼블릭 접근 가능하다고 가정)
    region = os.getenv("AWS_REGION", "ap-northeast-2")
    url = f"https://{bucket_name}.s3.{region}.amazonaws.com/{key}"
    return url


def calculate_elapsed_years(start_date: date, end_date: Optional[date] = None) -> float:
    """입주일(start_date)과 기준일(end_date) 사이의 경과 연수를 계산한다.

    - end_date를 지정하지 않으면 오늘 날짜를 기준으로 한다.
    - 일(day) 단위를 365로 나누어 연 단위 소수(float)로 반환한다.
    """

    if end_date is None:
        end_date = date.today()

    days = (end_date - start_date).days
    # 음수 방지를 위해 최소 0으로 보정
    return max(days / 365.0, 0.0)


def calculate_tenant_cost(
    total_repair_cost: float,
    elapsed_years: float,
    useful_life_years: float = 10.0,
) -> float:
    """국토부 가이드라인(벽지/장판 내구연수 10년 기준)에 따른 임차인 부담 비용을 계산한다.

    공식:
        임차인 부담비용 = 총 수리비 * (1 - 경과연수 / 내용연수)

    - useful_life_years 기본값을 10년으로 두어 벽지/장판을 기본 케이스로 가정한다.
    - (1 - 경과연수/내용연수)의 결과는 0~1 범위로 클램핑하여 과도한 값이 나오지 않도록 한다.
    """

    if total_repair_cost < 0:
        raise ValueError("총 수리비는 0 이상이어야 합니다.")

    if useful_life_years <= 0:
        raise ValueError("내용연수는 0보다 커야 합니다.")

    ratio = 1.0 - (elapsed_years / useful_life_years)

    # 0 ~ 1 범위로 제한 (경과 연수가 내용연수보다 크면 임차인 부담 0으로 간주)
    ratio = max(min(ratio, 1.0), 0.0)

    return total_repair_cost * ratio


def calculate_depreciation_rate(
    elapsed_years: float,
    useful_life_years: float = 10.0,
) -> float:
    """경과 연수 기준 감가상각 비율(임차인 부담 비율)을 계산한다.

    - 예: 반환값이 0.3이면 총 수리비의 30%를 임차인이 부담한다는 의미이다.
    - calculate_tenant_cost와 동일한 공식 기반으로, 0~1 범위 내 값으로 클램핑한다.
    """

    if useful_life_years <= 0:
        raise ValueError("내용연수는 0보다 커야 합니다.")

    ratio = 1.0 - (elapsed_years / useful_life_years)
    return max(min(ratio, 1.0), 0.0)

