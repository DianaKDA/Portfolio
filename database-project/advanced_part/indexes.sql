-- Поиск курсов по категории и статусу публикации
CREATE INDEX idx_course_category_published
    ON online_courses.course (category, is_published);

--  Платежи пользователя — история оплат и проверка доступа
CREATE INDEX idx_payment_user_status
    ON online_courses.payment (user_id, payment_status);
 
 -- Только активные записи на курсы
CREATE INDEX idx_enrollment_active
    ON online_courses.enrollment (course_id, user_id)
    WHERE completion_status = 'active';