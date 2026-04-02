"""Initial MEDSAI backend schema."""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision = "20260403_0001"
down_revision = None
branch_labels = None
depends_on = None


user_role_enum = sa.Enum("regular", "caregiver", "patient", name="userrole", native_enum=False)
care_code_status_enum = sa.Enum("active", "used", "expired", name="carecodestatus", native_enum=False)


def upgrade() -> None:
    op.create_table(
        "users",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, nullable=False),
        sa.Column("email", sa.String(length=255), nullable=True),
        sa.Column("password_hash", sa.String(length=255), nullable=True),
        sa.Column("role", user_role_enum, nullable=False),
        sa.Column("first_name", sa.String(length=120), nullable=True),
        sa.Column("last_name", sa.String(length=120), nullable=True),
        sa.Column("phone_number", sa.String(length=40), nullable=True),
        sa.Column("date_of_birth", sa.Date(), nullable=True),
        sa.Column("allergies", postgresql.ARRAY(sa.Text()), nullable=False, server_default="{}"),
        sa.Column("conditions", postgresql.ARRAY(sa.Text()), nullable=False, server_default="{}"),
        sa.Column("breakfast_time", sa.Time(), nullable=True),
        sa.Column("lunch_time", sa.Time(), nullable=True),
        sa.Column("dinner_time", sa.Time(), nullable=True),
        sa.Column("bedtime", sa.Time(), nullable=True),
        sa.Column("wakeup_time", sa.Time(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.execute("CREATE UNIQUE INDEX ix_users_email_unique ON users (email) WHERE email IS NOT NULL")

    op.create_table(
        "refresh_tokens",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("token_hash", sa.String(length=64), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("replaced_by_token_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_refresh_tokens_user_id", "refresh_tokens", ["user_id"])
    op.create_index("ix_refresh_tokens_token_hash_unique", "refresh_tokens", ["token_hash"], unique=True)

    op.create_table(
        "password_reset_tokens",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("token_hash", sa.String(length=64), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("used_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_password_reset_user_id", "password_reset_tokens", ["user_id"])
    op.create_index("ix_password_reset_token_hash_unique", "password_reset_tokens", ["token_hash"], unique=True)

    op.create_table(
        "device_sessions",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("device_token", sa.String(length=128), nullable=False),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_device_sessions_user_id", "device_sessions", ["user_id"])
    op.create_index("ix_device_sessions_device_token_unique", "device_sessions", ["device_token"], unique=True)

    op.create_table(
        "caregiver_relations",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, nullable=False),
        sa.Column("caregiver_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("patient_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.UniqueConstraint("caregiver_id", "patient_id", name="uq_caregiver_patient"),
    )
    op.create_index("ix_caregiver_relations_caregiver_id", "caregiver_relations", ["caregiver_id"])
    op.create_index("ix_caregiver_relations_patient_id", "caregiver_relations", ["patient_id"])

    op.create_table(
        "care_codes",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, nullable=False),
        sa.Column("code", sa.String(length=6), nullable=False),
        sa.Column("patient_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("caregiver_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("status", care_code_status_enum, nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_care_codes_code_unique", "care_codes", ["code"], unique=True)
    op.create_index("ix_care_codes_patient_id", "care_codes", ["patient_id"])
    op.create_index("ix_care_codes_caregiver_id", "care_codes", ["caregiver_id"])

    op.create_table(
        "medications",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, nullable=False),
        sa.Column("name", sa.Text(), nullable=False),
        sa.Column("aliases", postgresql.ARRAY(sa.Text()), nullable=False, server_default="{}"),
        sa.Column("image_urls", postgresql.ARRAY(sa.Text()), nullable=False, server_default="{}"),
        sa.Column("how_to_use", sa.Text(), nullable=True),
        sa.Column("side_effects", postgresql.ARRAY(sa.Text()), nullable=False, server_default="{}"),
        sa.Column("contraindications", postgresql.ARRAY(sa.Text()), nullable=False, server_default="{}"),
        sa.Column("food_rule", sa.Text(), nullable=False, server_default="none"),
        sa.Column("min_interval_hours", sa.Integer(), nullable=True),
        sa.Column("active_ingredients", postgresql.ARRAY(sa.Text()), nullable=False, server_default="{}"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.execute("CREATE UNIQUE INDEX ix_medications_name_unique_lower ON medications (lower(name))")

    op.create_table(
        "user_medications",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("medication_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("medications.id", ondelete="CASCADE"), nullable=False),
        sa.Column("dosage", sa.Text(), nullable=False),
        sa.Column("frequency_per_day", sa.Integer(), nullable=False),
        sa.Column("frequency_hours", sa.Integer(), nullable=True),
        sa.Column("start_date", sa.Date(), nullable=False),
        sa.Column("end_date", sa.Date(), nullable=False),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.execute("CREATE INDEX ix_user_medications_user_active ON user_medications (user_id, is_active)")
    op.create_index("ix_user_medications_medication_id", "user_medications", ["medication_id"])

    op.create_table(
        "appointments",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("title", sa.Text(), nullable=False),
        sa.Column("doctor_name", sa.Text(), nullable=True),
        sa.Column("appointment_time", sa.DateTime(timezone=True), nullable=False),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.execute("CREATE INDEX ix_appointments_user_time ON appointments (user_id, appointment_time)")

    op.create_table(
        "search_history",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("search_query", sa.Text(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.execute("CREATE INDEX ix_search_history_user_created_at_desc ON search_history (user_id, created_at DESC)")


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_search_history_user_created_at_desc")
    op.drop_table("search_history")

    op.execute("DROP INDEX IF EXISTS ix_appointments_user_time")
    op.drop_table("appointments")

    op.drop_index("ix_user_medications_medication_id", table_name="user_medications")
    op.execute("DROP INDEX IF EXISTS ix_user_medications_user_active")
    op.drop_table("user_medications")

    op.execute("DROP INDEX IF EXISTS ix_medications_name_unique_lower")
    op.drop_table("medications")

    op.drop_index("ix_care_codes_caregiver_id", table_name="care_codes")
    op.drop_index("ix_care_codes_patient_id", table_name="care_codes")
    op.drop_index("ix_care_codes_code_unique", table_name="care_codes")
    op.drop_table("care_codes")

    op.drop_index("ix_caregiver_relations_patient_id", table_name="caregiver_relations")
    op.drop_index("ix_caregiver_relations_caregiver_id", table_name="caregiver_relations")
    op.drop_table("caregiver_relations")

    op.drop_index("ix_device_sessions_device_token_unique", table_name="device_sessions")
    op.drop_index("ix_device_sessions_user_id", table_name="device_sessions")
    op.drop_table("device_sessions")

    op.drop_index("ix_password_reset_token_hash_unique", table_name="password_reset_tokens")
    op.drop_index("ix_password_reset_user_id", table_name="password_reset_tokens")
    op.drop_table("password_reset_tokens")

    op.drop_index("ix_refresh_tokens_token_hash_unique", table_name="refresh_tokens")
    op.drop_index("ix_refresh_tokens_user_id", table_name="refresh_tokens")
    op.drop_table("refresh_tokens")

    op.execute("DROP INDEX IF EXISTS ix_users_email_unique")
    op.drop_table("users")
