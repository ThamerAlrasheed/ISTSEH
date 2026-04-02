from fastapi import APIRouter

from app.api.v1.routers import (
    appointments,
    auth,
    care_codes,
    caregiver,
    drug_intel,
    me,
    medications,
    search_history,
)


api_router = APIRouter()
api_router.include_router(auth.router, prefix="/auth", tags=["auth"])
api_router.include_router(me.router, prefix="/me", tags=["me"])
api_router.include_router(caregiver.router, prefix="/caregiver", tags=["caregiver"])
api_router.include_router(care_codes.router, prefix="/care-codes", tags=["care-codes"])
api_router.include_router(medications.router, tags=["medications"])
api_router.include_router(appointments.router, prefix="/appointments", tags=["appointments"])
api_router.include_router(search_history.router, prefix="/search-history", tags=["search-history"])
api_router.include_router(drug_intel.router, tags=["drug-intel"])
