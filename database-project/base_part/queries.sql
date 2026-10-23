-- Получаем список опубликованных курсов категории «Data Science» стоимостью не выше 60, отсортированных по цене.
SELECT
    c.course_id,
    c.title,
    c.level,
    c.price
FROM online_courses.course c
WHERE c.category = 'Data Science'
  AND c.is_published = TRUE
  AND c.price <= 60.00
ORDER BY c.price;

-- Для каждого опубликованного курса выводим имя преподавателя, количество отзывов и средний рейтинг.
-- Показываем только те курсы, у которых есть хотя бы один отзыв.
SELECT
    c.title                 AS course_title,
    i.full_name             AS instructor_name,
    COUNT(r.review_id)      AS review_count,
    ROUND(AVG(r.rating), 2) AS avg_rating
FROM online_courses.course c
JOIN online_courses.instructor i
    ON i.instructor_id = c.instructor_id
JOIN online_courses.review r
    ON r.course_id = c.course_id
WHERE c.is_published = TRUE
GROUP BY c.course_id, c.title, i.full_name
HAVING COUNT(r.review_id) > 0
ORDER BY avg_rating DESC;

-- Находим пользователей, которые записаны хотя бы на один курс, но ещё не получили ни одного сертификата.
SELECT
    u.user_id,
    u.full_name,
    u.country
FROM online_courses.user u
WHERE EXISTS (
    SELECT 1
    FROM online_courses.enrollment e
    WHERE e.user_id = u.user_id
)
  AND u.user_id NOT IN (
    SELECT cert.user_id
    FROM online_courses.certificate cert
)
ORDER BY u.full_name;

-- Присваиваем каждому курсу метку популярности на основе числа записавшихся пользователей: «высокая», «средняя» или «низкая».
SELECT
    c.title,
    c.category,
    COUNT(e.user_id) AS enrolled_count,
    CASE
        WHEN COUNT(e.user_id) >= 5 THEN 'высокая'
        WHEN COUNT(e.user_id) >= 3 THEN 'средняя'
        ELSE                            'низкая'
    END AS popularity
FROM online_courses.course c
LEFT JOIN online_courses.enrollment e  -- берём все курсы
    ON e.course_id = c.course_id
WHERE c.is_published = TRUE
GROUP BY c.course_id, c.title, c.category
ORDER BY enrolled_count DESC;

-- Показываем суммарную выручку (статус completed), количество возвратов и долю возвратов от общего числа платежей для каждой категории.
SELECT
    c.category,
    COUNT(p.payment_id)
        FILTER (WHERE p.payment_status = 'completed')     AS completed_count,
    ROUND(SUM(p.amount)
        FILTER (WHERE p.payment_status = 'completed'), 2) AS total_revenue,
    COUNT(p.payment_id)
        FILTER (WHERE p.payment_status = 'refunded')      AS refund_count,
    ROUND(
        100.0 * COUNT(p.payment_id) FILTER (WHERE p.payment_status = 'refunded')
        / NULLIF(COUNT(p.payment_id), 0), 2)              AS refund_rate_pct
FROM online_courses.payment p
JOIN online_courses.course c
    ON c.course_id = p.course_id
GROUP BY c.category
ORDER BY total_revenue DESC;

-- Находим опубликованные курсы, на которых есть записавшиеся пользователи, но ни один из них не оставил отзыв.
SELECT
    c.course_id,
    c.title,
    c.category,
    COUNT(e.user_id) AS enrolled_count
FROM online_courses.course c
JOIN online_courses.enrollment e
    ON e.course_id = c.course_id
LEFT JOIN online_courses.review r
    ON r.course_id = c.course_id
WHERE c.is_published = TRUE
  AND r.review_id IS NULL
GROUP BY c.course_id, c.title, c.category
ORDER BY enrolled_count DESC;

-- Для каждого преподавателя определяем три его самых прибыльных курса по сумме успешных платежей.
WITH course_revenue AS (
    SELECT
        c.instructor_id,
        c.course_id,
        c.title,
        SUM(p.amount) AS total_revenue,
        RANK() OVER (
            PARTITION BY c.instructor_id
            ORDER BY SUM(p.amount) DESC
        ) AS rn
    FROM online_courses.course c
    JOIN online_courses.payment p
        ON p.course_id = c.course_id
    WHERE p.payment_status = 'completed'
    GROUP BY c.instructor_id, c.course_id, c.title
)
SELECT
    i.full_name                AS instructor_name,
    cr.title                   AS course_title,
    ROUND(cr.total_revenue, 2) AS total_revenue,
    cr.rn                      AS revenue_rank
FROM course_revenue cr
JOIN online_courses.instructor i
    ON i.instructor_id = cr.instructor_id
WHERE cr.rn <= 3
ORDER BY i.full_name, cr.rn;

-- Для каждого пользователя выводим список его курсов и накопительный средний прогресс по дате записи.
WITH user_progress AS (
    SELECT
        e.user_id,
        c.title AS course_title,
        e.enrolled_at,
        e.progress_percentage,
        e.completion_status,
        AVG(e.progress_percentage) OVER (
            PARTITION BY e.user_id
            ORDER BY e.enrolled_at
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS running_avg
    FROM online_courses.enrollment e
    JOIN online_courses.course c
        ON c.course_id = e.course_id
)
SELECT
    u.full_name,
    up.course_title,
    up.enrolled_at,
    up.progress_percentage,
    up.completion_status,
    ROUND(up.running_avg, 2) AS running_avg_progress
FROM user_progress up
JOIN online_courses.user u
    ON u.user_id = up.user_id
ORDER BY u.full_name, up.enrolled_at;

-- Количество новых записей на курсы по месяцам и сравнение каждого месяца с предыдущим с помощью оконной функции LAG().
-- Показывает прирост или падение активности.
WITH monthly_enrollments AS (
    SELECT
        DATE_TRUNC('month', e.enrolled_at) AS month,  -- обрезаем дату до начала месяца
        COUNT(*) AS new_enrollments
    FROM online_courses.enrollment e
    GROUP BY 1
)
SELECT
    TO_CHAR(month, 'YYYY-MM') AS month,
    new_enrollments,
    LAG(new_enrollments) OVER ( ORDER BY month ) AS prev_month,
    new_enrollments - LAG(new_enrollments) OVER ( ORDER BY month ) AS diff
FROM monthly_enrollments
ORDER BY month;

-- Сводка по каждому преподавателю: сколько у него курсов, сколько всего студентов, средний рейтинг его курсов и суммарная выручка.
-- Используется цепочка CTE.
WITH
instructor_courses AS (
    SELECT
        c.instructor_id,
        COUNT(c.course_id) AS course_count
    FROM online_courses.course c
    WHERE c.is_published = TRUE
    GROUP BY c.instructor_id
),
instructor_students AS (
    SELECT
        c.instructor_id,
        COUNT(DISTINCT e.user_id) AS student_count
    FROM online_courses.enrollment e
    JOIN online_courses.course c
        ON c.course_id = e.course_id
    GROUP BY c.instructor_id
),
instructor_ratings AS (
    SELECT
        c.instructor_id,
        ROUND(AVG(r.rating), 2) AS avg_rating
    FROM online_courses.review r
    JOIN online_courses.course c
        ON c.course_id = r.course_id
    GROUP BY c.instructor_id
),
instructor_revenue AS (
    SELECT
        c.instructor_id,
        ROUND(SUM(p.amount), 2) AS total_revenue
    FROM online_courses.payment p
    JOIN online_courses.course c
        ON c.course_id = p.course_id
    WHERE p.payment_status = 'completed'
    GROUP BY c.instructor_id
)
SELECT
    i.full_name AS instructor_name,
    i.specialization,
    ic.course_count,
    COALESCE(ist.student_count, 0) AS student_count,
    COALESCE(ir.avg_rating, 0)     AS avg_rating,
    COALESCE(irv.total_revenue, 0) AS total_revenue
FROM online_courses.instructor i
JOIN instructor_courses ic        ON ic.instructor_id  = i.instructor_id
LEFT JOIN instructor_students ist ON ist.instructor_id = i.instructor_id
LEFT JOIN instructor_ratings ir   ON ir.instructor_id  = i.instructor_id
LEFT JOIN instructor_revenue irv  ON irv.instructor_id = i.instructor_id
ORDER BY irv.total_revenue DESC;

-- Находим пользователей, которые завершили (получили сертификат) минимум два разных курса одного и того же преподавателя.
-- Признак высокой лояльности к преподавателю.
SELECT
    u.full_name                    AS user_name,
    i.full_name                    AS instructor_name,
    COUNT(DISTINCT cert.course_id) AS completed_courses
FROM online_courses.certificate cert
JOIN online_courses.course c
    ON c.course_id = cert.course_id
JOIN online_courses.instructor i
    ON i.instructor_id = c.instructor_id
JOIN online_courses.user u
    ON u.user_id = cert.user_id
GROUP BY u.user_id, u.full_name,
         i.instructor_id, i.full_name
HAVING COUNT(DISTINCT cert.course_id) >= 2
ORDER BY completed_courses DESC;

-- Вычисляем медианную и максимальную длительность урока для каждой категории курсов.
SELECT
    c.category,
    COUNT(l.lesson_id)                                          AS lesson_count,
    ROUND(AVG(l.duration_min), 1)                               AS avg_duration_min,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY l.duration_min) AS median_duration_min,
    MAX(l.duration_min)                                         AS max_duration_min
FROM online_courses.lesson l
JOIN online_courses.course c
    ON c.course_id = l.course_id
GROUP BY c.category
ORDER BY avg_duration_min DESC;