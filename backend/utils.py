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
from urllib.parse import urlparse

import boto3
import magic
from fastapi import UploadFile


# 전역 S3 클라이언트 (필요 시 리전/엔드포인트를 환경 변수로 조정)
_s3_client = boto3.client("s3", region_name=os.getenv("AWS_REGION", "ap-northeast-2"))

MAX_IMAGE_SIZE_BYTES = 10 * 1024 * 1024  # 10MB 제한
ALLOWED_IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp"}
ALLOWED_IMAGE_MIME_TYPES = {"image/jpeg", "image/png", "image/webp"}

# 확장자 ↔ 허용 MIME (확장자 위조·이중 확장자 방지용 교차 검증)
_EXTENSION_TO_EXPECTED_MIME = {
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".png": "image/png",
    ".webp": "image/webp",
}

# 벽지·장판 등 소모성 마감재 기본 내용연수(년) — 국토부 가이드라인 예시값, 호출부에서 덮어쓸 수 있음
DEFAULT_USEFUL_LIFE_YEARS = 10.0

# magic 검사 시 사용할 최대 샘플 크기 (바이트). JPEG/PNG/WebP 식별에 충분하면서 polyglot 일부 회피
_MAGIC_SAMPLE_BYTES = 256 * 1024


def compute_image_hash_sha256(data: bytes) -> str:
    """업로드 이미지 바이트에 대한 SHA-256 지문(64자 16진 image_hash)을 반환한다.

    DB의 DamageImage.file_hash, RepairEstimate.image_hash 등 무결성 필드에 그대로 저장한다.
    """

    return hashlib.sha256(data).hexdigest()


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


def _strict_detect_and_match_image_mime(file_bytes: bytes, filename: Optional[str]) -> str:
    """python-magic으로 실제 MIME을 검출하고, 확장자·허용 목록과 교차 검증한다."""

    ext = _get_extension(filename)
    if ext not in ALLOWED_IMAGE_EXTENSIONS:
        raise ValueError("허용되지 않은 파일 확장자입니다. (.jpg, .jpeg, .png, .webp 만 허용)")

    expected = _EXTENSION_TO_EXPECTED_MIME.get(ext)
    if expected is None:
        raise ValueError("허용되지 않은 파일 확장자입니다.")

    if not file_bytes:
        raise ValueError("빈 파일은 업로드할 수 없습니다.")

    sample = file_bytes if len(file_bytes) <= _MAGIC_SAMPLE_BYTES else file_bytes[:_MAGIC_SAMPLE_BYTES]
    detected_mime = magic.from_buffer(sample, mime=True)

    if detected_mime not in ALLOWED_IMAGE_MIME_TYPES:
        raise ValueError(
            "실제 파일 내용이 허용된 이미지 형식이 아닙니다. (python-magic 검증 실패)"
        )

    if detected_mime != expected:
        raise ValueError(
            "파일 확장자와 실제 이미지 형식이 일치하지 않습니다. "
            f"(확장자 기대: {expected}, 실제: {detected_mime})"
        )

    return detected_mime


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
    - 확장자 화이트리스트
    - python-magic으로 실제 바이트 기반 MIME 검증 + 확장자와의 일치(위조 방지)
    - 클라이언트 Content-Type이 있으면 검출 MIME과 일치 여부 확인

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

    raw = bytes(buf)
    detected_mime = _strict_detect_and_match_image_mime(raw, upload_file.filename)

    if upload_file.content_type:
        ct = upload_file.content_type.split(";")[0].strip().lower()
        if ct not in ALLOWED_IMAGE_MIME_TYPES:
            raise ValueError("요청의 Content-Type이 허용된 이미지가 아닙니다.")
        if ct != detected_mime:
            raise ValueError(
                "요청 Content-Type과 실제 파일 내용이 일치하지 않습니다. "
                f"(헤더: {ct}, 실제: {detected_mime})"
            )

    return raw, detected_mime


async def calculate_sha256_from_bytes(data: bytes) -> str:
    """바이트 데이터의 SHA-256 해시를 계산한다 (비동기 API 호환용 래퍼)."""

    return compute_image_hash_sha256(data)


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


def parse_s3_public_bucket_key(url: str) -> Tuple[str, str]:
    """퍼블릭 가상 호스팅 형태의 S3 URL에서 버킷명과 오브젝트 키를 추출한다."""

    parsed = urlparse(url)
    host = parsed.netloc
    if ".s3." not in host or not host.endswith(".amazonaws.com"):
        raise ValueError("지원하지 않는 S3 URL 형식입니다.")
    bucket = host.split(".s3.", 1)[0]
    key = parsed.path.lstrip("/")
    if not key:
        raise ValueError("S3 URL에 오브젝트 키가 없습니다.")
    return bucket, key


def download_bytes_from_s3_url(url: str) -> Tuple[bytes, str]:
    """S3 퍼블릭 URL에서 객체 바이트와 Content-Type을 가져온다 (Celery 워커 분석용)."""

    bucket, key = parse_s3_public_bucket_key(url)
    resp = _s3_client.get_object(Bucket=bucket, Key=key)
    body = resp["Body"].read()
    content_type = resp.get("ContentType") or "application/octet-stream"
    return body, content_type


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


def compute_depreciation_factor(elapsed_years: float, useful_life_years: float) -> float:
    """감가 후 임차인 부담 비율: (1 - elapsed/useful), 0~1로 클램핑."""

    if useful_life_years <= 0:
        raise ValueError("내용연수(Years_useful)는 0보다 커야 합니다.")

    factor = 1.0 - (elapsed_years / useful_life_years)
    return max(min(factor, 1.0), 0.0)


def compute_moliti_depreciation_tenant_cost(
    cost_total: float,
    years_elapsed: float,
    years_useful: float = DEFAULT_USEFUL_LIFE_YEARS,
) -> float:
    """국토부 가이드라인에 따른 임차인 부담 수리비(감가상각 적용).

    수식:
        Cost_tenant = Cost_total × (1 - Years_elapsed / Years_useful)

    - 벽지·장판 등 소모성 마감재의 내용연수(Years_useful) 기본값은 10년이며,
      마감재 종류·계약에 맞게 호출부에서 다른 값을 넘길 수 있다.
    - 경과 연수가 내용연수를 초과하면 임차인 부담은 0으로 본다(비율 하한 0).
    """

    if cost_total < 0:
        raise ValueError("총 수리비(Cost_total)는 0 이상이어야 합니다.")

    factor = compute_depreciation_factor(years_elapsed, years_useful)
    return cost_total * factor


def calculate_tenant_cost(
    total_repair_cost: float,
    elapsed_years: float,
    useful_life_years: float = DEFAULT_USEFUL_LIFE_YEARS,
) -> float:
    """`compute_moliti_depreciation_tenant_cost`와 동일 (기존 코드 호환용 이름)."""

    return compute_moliti_depreciation_tenant_cost(
        total_repair_cost, elapsed_years, useful_life_years
    )


def calculate_depreciation_rate(
    elapsed_years: float,
    useful_life_years: float = DEFAULT_USEFUL_LIFE_YEARS,
) -> float:
    """경과 연수 기준 임차인 부담 비율(감가상각 후 임차인이 부담하는 비중, 0~1)."""

    return compute_depreciation_factor(elapsed_years, useful_life_years)

