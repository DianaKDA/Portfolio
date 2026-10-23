-- Представление 1. Сводка по курсу (не материализованное, необновляемое)
-- Для каждого курса показывает преподавателя, рейтинг, число студентов и уроков.
CREATE OR REPLACE VIEW online_courses.v_course_summary AS
SELECT
    c.course_id,
    c.title AS course_title,
    c.category,
    c.level,
    c.price,
    c.is_published,
    i.instructor_id,
    i.full_name AS instructor_name,
    i.specialization,
    COUNT(e.user_id)                      AS enrolled_count,
    COUNT(cert.certificate_id)            AS certified_count,
    COUNT(DISTINCT l.lesson_id)           AS lesson_count,
    COALESCE(ROUND(AVG(r.rating), 2), 0)  AS avg_rating,
    COUNT(DISTINCT r.review_id)           AS review_count
FROM online_courses.course c
JOIN online_courses.instructor i
    ON i.instructor_id = c.instructor_id
LEFT JOIN online_courses.enrollment e
    ON e.course_id = c.course_id
LEFT JOIN online_courses.certificate cert
    ON cert.course_id = c.course_id
LEFT JOIN online_courses.lesson l
    ON l.course_id = c.course_id
LEFT JOIN online_courses.review r
    ON r.course_id = c.course_id
GROUP BY
    c.course_id, c.title, c.category, c.level,
    c.price, c.is_published,
    i.instructor_id, i.full_name, i.specialization;

-- Пример использования:
-- SELECT * FROM online_courses.v_course_summary
-- WHERE is_published = TRUE
-- ORDER BY avg_rating DESC;

-- Представление 2. Аналитика по преподавателям (материализованное, необновляемое)
-- Показывает сводку по каждому преподавателю: сколько курсов,
-- студентов, суммарная выручка и средний рейтинг.
CREATE MATERIALIZED VIEW online_courses.mv_instructor_stats AS
WITH
inst_courses AS (
    SELECT
        c.instructor_id,
        COUNT(c.course_id) AS course_count,
        COUNT(c.course_id)
            FILTER (WHERE c.is_published) AS published_count
    FROM online_courses.course c
    GROUP BY c.instructor_id
),
inst_students AS (
    SELECT
        c.instructor_id,
        COUNT(e.user_id) AS student_count
    FROM online_courses.enrollment e
    JOIN online_courses.course c
        ON c.course_id = e.course_id
    GROUP BY c.instructor_id
),
inst_revenue AS (
    SELECT
        c.instructor_id,
        ROUND(SUM(p.amount), 2) AS total_revenue,
        COUNT(p.payment_id) AS payment_count
    FROM online_courses.payment p
    JOIN online_courses.course c
        ON c.course_id = p.course_id
    WHERE p.payment_status = 'completed'
    GROUP BY c.instructor_id
),
inst_ratings AS (
    SELECT
        c.instructor_id,
        ROUND(AVG(r.rating), 2) AS avg_rating,
        COUNT(r.review_id) AS review_count
    FROM online_courses.review r
    JOIN online_courses.course c
        ON c.course_id = r.course_id
    GROUP BY c.instructor_id
)
SELECT
    i.instructor_id,
    i.full_name AS instructor_name,
    i.specialization,
    i.hire_date,
    COALESCE(ic.course_count, 0)           AS course_count,
    COALESCE(ic.published_count, 0)        AS published_count,
    COALESCE(ist.student_count, 0)         AS student_count,
    COALESCE(ir.total_revenue, 0)          AS total_revenue,
    COALESCE(ir.payment_count, 0)          AS payment_count,
    COALESCE(irt.avg_rating, 0)            AS avg_rating,
    COALESCE(irt.review_count, 0)          AS review_count
FROM online_courses.instructor i
LEFT JOIN inst_courses  ic  ON ic.instructor_id  = i.instructor_id
LEFT JOIN inst_students ist ON ist.instructor_id = i.instructor_id
LEFT JOIN inst_revenue  ir  ON ir.instructor_id  = i.instructor_id
LEFT JOIN inst_ratings  irt ON irt.instructor_id = i.instructor_id

-- Обновление материализованного представления:
-- REFRESH MATERIALIZED VIEW online_courses.mv_instructor_stats;

-- Пример использования:
-- SELECT instructor_name, course_count, student_count,
--        total_revenue, avg_rating
-- FROM online_courses.mv_instructor_stats
-- WHERE published_count > 0
-- ORDER BY total_revenue DESC;