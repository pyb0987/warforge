# 기술 스택 결정: Godot 4

## 날짜
2026-03-26

## 결정
게임 엔진으로 **Godot 4** (GDScript) 채택.

## 대안 비교

| | Godot 4 | Unity 2D | Phaser (웹) |
|---|---|---|---|
| 2D 네이티브 | ★★★ | ★★☆ (3D 위 2D) | ★★☆ |
| 프로토타이핑 속도 | 매우 빠름 | 보통 | 빠름 |
| SC1식 유닛 AI | Navigation2D + Area2D 내장 | 제한적 | 직접 구현 |
| 멀티플랫폼 | PC/모바일/웹 | PC/모바일 | 웹 전용 |
| 라이선스 | MIT | 유료 전환 리스크 | MIT |
| 기존 코드 이식 | GDScript ≈ Python (시뮬 이식 용이) | C# (재작성) | TS (재작성) |

## 선택 사유

1. **네이티브 2D 엔진** — 이 프로젝트는 2D 대규모 군집 전투. Godot의 2D가 1급 시민
2. **GDScript ≈ Python** — 현재 Python 시뮬레이터 로직 이식이 자연스러움
3. **SC1식 전투 내장 도구** — Area2D(사거리 감지), NavigationAgent2D(이동), 틱 기반 물리
4. **경량 에디터** — 200MB, 빠른 이터레이션
5. **MIT 라이선스** — 상업적 리스크 없음
6. **멀티플랫폼** — 모바일 + 웹 동시 지원 (rendering.md 목표와 일치)

## 파이프라인

```
현재 Python 시뮬 (1D CP 근사)
  → Godot 전투 엔진 (2D 실제 전투: 사거리/AS/MS)
    → 전투 엔진 기반 시뮬 검증 (정확한 승률)
      → 밸런싱 재조정
```

## 영향

- rendering.md의 "프레임 스프라이트" 방식은 Godot AnimatedSprite2D로 직접 구현 가능
- 400유닛 렌더링은 Godot의 CanvasItem 배칭 + GPU 인스턴싱으로 대응
- Python 시뮬은 빠른 배치 검증용으로 병행 유지
