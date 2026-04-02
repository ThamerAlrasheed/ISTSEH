from enum import StrEnum


class UserRole(StrEnum):
    REGULAR = "regular"
    CAREGIVER = "caregiver"
    PATIENT = "patient"


class CareCodeStatus(StrEnum):
    ACTIVE = "active"
    USED = "used"
    EXPIRED = "expired"


class FoodRule(StrEnum):
    NONE = "none"
    BEFORE_FOOD = "before_food"
    AFTER_FOOD = "after_food"
