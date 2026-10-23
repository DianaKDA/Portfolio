-- Возвращает процент студентов, получивших
-- сертификат, от общего числа записавшихся на курс
CREATE OR REPLACE FUNCTION online_courses.get_course_completion_rate(
    p_course_id INT
)
RETURNS NUMERIC
LANGUAGE sql
AS $$
    SELECT ROUND(
        100.0 * COUNT(cert.user_id) / NULLIF(COUNT(e.user_id), 0), 2
    )
    FROM online_courses.enrollment e
    LEFT JOIN online_courses.certificate cert
        ON cert.course_id = e.course_id
        AND cert.user_id = e.user_id
    WHERE e.course_id = p_course_id;
$$;

-- Пример использования:
-- SELECT online_courses.get_course_completion_rate(1);

-- Проверка — может ли пользователь оставить отзыв
CREATE OR REPLACE FUNCTION online_courses.can_user_review(
    p_user_id INT,
    p_course_id INT
)
RETURNS BOOLEAN
LANGUAGE sql
AS $$
    SELECT
        EXISTS (
            SELECT 1 FROM online_courses.enrollment e
            WHERE e.user_id = p_user_id AND e.course_id = p_course_id
        )
        AND NOT EXISTS (
            SELECT 1 FROM online_courses.review r
            WHERE r.user_id = p_user_id AND r.course_id = p_course_id
        );
$$;

-- Пример использования:
-- SELECT online_courses.can_user_review(1, 2);

--  Процедура 1. Запись пользователя на курс с проверками
CREATE OR REPLACE PROCEDURE online_courses.enroll_user(
    p_user_id INT,
    p_course_id INT,
    p_amount NUMERIC
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_is_published     BOOLEAN;
    v_already_enrolled BOOLEAN;
    v_already_paid     BOOLEAN;
    v_new_payment_id   INT;
BEGIN
    SELECT is_published
    INTO   v_is_published
    FROM   online_courses.course
    WHERE  course_id = p_course_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Курс % не найден.', p_course_id;
    END IF;

    IF NOT v_is_published THEN
        RAISE EXCEPTION 'Курс % не опубликован и недоступен для записи.', p_course_id;
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM online_courses.enrollment
        WHERE user_id = p_user_id AND course_id = p_course_id
    ) INTO v_already_enrolled;

    IF v_already_enrolled THEN
        RAISE EXCEPTION 'Пользователь % уже записан на курс %.', p_user_id, p_course_id;
    END IF;

    -- мб
    SELECT EXISTS (
        SELECT 1 FROM online_courses.payment
        WHERE user_id = p_user_id
          AND course_id = p_course_id
          AND payment_status = 'completed'
    ) INTO v_already_paid;

    IF v_already_paid THEN
        RAISE EXCEPTION 'Пользователь % уже оплатил курс %.', p_user_id, p_course_id;
    END IF;

    -- Создаём платёж
    SELECT COALESCE(MAX(payment_id), 0) + 1
    INTO   v_new_payment_id
    FROM   online_courses.payment;

    INSERT INTO online_courses.payment
        (payment_id, user_id, course_id, amount, payment_status, paid_at)
    VALUES
        (v_new_payment_id, p_user_id, p_course_id,
         p_amount, 'completed', CURRENT_TIMESTAMP);

    -- Создаём запись на курс
    INSERT INTO online_courses.enrollment
        (user_id, course_id, enrolled_at,
         progress_percentage, completion_status, last_access_at)
    VALUES
        (p_user_id, p_course_id, CURRENT_DATE,
         0.00, 'active', CURRENT_TIMESTAMP);

    RAISE NOTICE 'Пользователь % успешно записан на курс %.', p_user_id, p_course_id;
END;
$$;

-- Пример использования:
-- CALL online_courses.enroll_user(25, 16, 59.99);

--  Процедура 2. Выдача сертификата при завершении курса
CREATE OR REPLACE PROCEDURE online_courses.award_certificate(
    p_user_id   INT,
    p_course_id INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_status      VARCHAR(20);
    v_progress    NUMERIC(5,2);
    v_cert_exists BOOLEAN;
    v_new_cert_id INT;
BEGIN
    SELECT completion_status, progress_percentage
    INTO   v_status, v_progress
    FROM   online_courses.enrollment
    WHERE  user_id = p_user_id
      AND  course_id = p_course_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Пользователь % не записан на курс %.', p_user_id, p_course_id;
    END IF;

    IF v_status <> 'completed' THEN
        RAISE EXCEPTION
            'Невозможно выдать сертификат: статус записи — %, ожидается completed.',
            v_status;
    END IF;

    IF v_progress < 100 THEN
        RAISE EXCEPTION USING MESSAGE = FORMAT(
            'Невозможно выдать сертификат: прогресс %s %s%%, ожидается 100%%.',
            p_user_id, v_progress
        );
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM online_courses.certificate
        WHERE user_id = p_user_id
          AND course_id = p_course_id
    ) INTO v_cert_exists;

    IF v_cert_exists THEN
        RAISE EXCEPTION
            'Сертификат пользователю % на курс % уже выдан.',
            p_user_id, p_course_id;
    END IF;

    -- Выдаём сертификат
    SELECT COALESCE(MAX(certificate_id), 0) + 1
    INTO   v_new_cert_id
    FROM   online_courses.certificate;

    INSERT INTO online_courses.certificate
        (certificate_id, user_id, course_id, issued_at)
    VALUES
        (v_new_cert_id, p_user_id, p_course_id, CURRENT_DATE);

    RAISE NOTICE 'Сертификат % выдан пользователю % за курс %.',
        v_new_cert_id, p_user_id, p_course_id;
END;
$$;

-- Пример использования:
-- CALL online_courses.award_certificate(1, 1);

--  Процедура 3. Обновление прогресса и автоматическое завершение курса.
--  Если прогресс достигает 100% — автоматически переводит
--  статус enrollment в 'completed' и вызывает award_certificate.
CREATE OR REPLACE PROCEDURE online_courses.update_progress(
    p_user_id      INT,
    p_course_id    INT,
    p_new_progress NUMERIC
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_current_status VARCHAR(20);
BEGIN
    SELECT completion_status
    INTO   v_current_status
    FROM   online_courses.enrollment
    WHERE  user_id   = p_user_id
      AND  course_id = p_course_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Пользователь % не записан на курс %.', p_user_id, p_course_id;
    END IF;

    IF v_current_status = 'dropped' THEN
        RAISE EXCEPTION 'Невозможно обновить прогресс: пользователь % бросил курс %.', p_user_id, p_course_id;
    END IF;

    IF v_current_status = 'completed' THEN
        RAISE EXCEPTION 'Курс % уже завершён пользователем %.', p_course_id, p_user_id;
    END IF;

    IF p_new_progress < 0 OR p_new_progress > 100 THEN
        RAISE EXCEPTION 'Прогресс должен быть в диапазоне 0–100, получено: %.', p_new_progress;
    END IF;

    UPDATE online_courses.enrollment
    SET
        progress_percentage = p_new_progress,
        last_access_at = CURRENT_TIMESTAMP,
        completion_status = CASE
            WHEN p_new_progress = 100 THEN 'completed'
            ELSE 'active'
        END
    WHERE user_id   = p_user_id
      AND course_id = p_course_id;

    RAISE NOTICE USING MESSAGE = FORMAT(
        'Прогресс пользователя %s на курсе %s обновлён до %s%%.',
        p_user_id, p_course_id, p_new_progress
    );

    IF p_new_progress = 100 THEN
        CALL online_courses.award_certificate(p_user_id, p_course_id);
    END IF;
END;
$$;

-- Пример использования:
-- CALL online_courses.update_progress(5, 1, 100);