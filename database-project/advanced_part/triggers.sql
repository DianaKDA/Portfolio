-- SCD 4 для таблицы enrollment
CREATE TABLE IF NOT EXISTS online_courses.enrollment_history (
    history_id          SERIAL          PRIMARY KEY,
    user_id             INT             NOT NULL,
    course_id           INT             NOT NULL,
    enrolled_at         DATE            NOT NULL,
    progress_percentage NUMERIC(5, 2)   NOT NULL,
    completion_status   VARCHAR(20)     NOT NULL,
    last_access_at      TIMESTAMP,
    changed_at          TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    operation_type      VARCHAR(10)     NOT NULL,
    CONSTRAINT chk_enrollment_history_operation
        CHECK (operation_type IN ('UPDATE', 'DELETE'))
);

-- Триггер 1. Сохранение истории enrollment
CREATE OR REPLACE FUNCTION online_courses.trg_save_enrollment_history()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO online_courses.enrollment_history (
        user_id,
        course_id,
        enrolled_at,
        progress_percentage,
        completion_status,
        last_access_at,
        changed_at,
        operation_type
    )
    VALUES (
        OLD.user_id,
        OLD.course_id,
        OLD.enrolled_at,
        OLD.progress_percentage,
        OLD.completion_status,
        OLD.last_access_at,
        CURRENT_TIMESTAMP,
        TG_OP
    );

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_enrollment_history
    BEFORE UPDATE OR DELETE
    ON online_courses.enrollment
    FOR EACH ROW
    EXECUTE FUNCTION online_courses.trg_save_enrollment_history();

-- Триггер 2. Запрет отзыва без записи
CREATE OR REPLACE FUNCTION online_courses.trg_check_review_eligibility()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_status VARCHAR(20);
BEGIN
    SELECT completion_status
    INTO   v_status
    FROM   online_courses.enrollment
    WHERE  user_id   = NEW.user_id
      AND  course_id = NEW.course_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Пользователь % не записан на курс % и не может оставить отзыв.',
            NEW.user_id, NEW.course_id;
    END IF;

    IF v_status = 'dropped' THEN
        RAISE EXCEPTION
            'Пользователь % бросил курс % и не может оставить отзыв.',
            NEW.user_id, NEW.course_id;
    END IF;

    -- Обновляем updated_at при редактировании отзыва
    IF TG_OP = 'UPDATE' THEN
        NEW.updated_at := CURRENT_TIMESTAMP;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_review_eligibility
    BEFORE INSERT OR UPDATE
    ON online_courses.review
    FOR EACH ROW
    EXECUTE FUNCTION online_courses.trg_check_review_eligibility();