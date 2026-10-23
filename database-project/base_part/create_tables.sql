DROP SCHEMA IF EXISTS online_courses CASCADE;

CREATE SCHEMA online_courses;

CREATE TABLE online_courses.user (
    user_id           INT PRIMARY KEY,
    full_name         VARCHAR(150) NOT NULL,
    email             VARCHAR(255) NOT NULL UNIQUE,
    registration_data DATE NOT NULL,
    country           VARCHAR(100)
);

CREATE TABLE online_courses.instructor (
    instructor_id  INT PRIMARY KEY,
    full_name      VARCHAR(150) NOT NULL,
    email          VARCHAR(255) NOT NULL UNIQUE,
    specialization VARCHAR(120) NOT NULL,
    hire_date      DATE NOT NULL
);

CREATE TABLE online_courses.course (
    course_id     INT PRIMARY KEY,
    instructor_id INT NOT NULL,
    title         VARCHAR(200) NOT NULL,
    category      VARCHAR(100) NOT NULL,
    level         VARCHAR(20)  NOT NULL,
    price         NUMERIC(10, 2) NOT NULL,
    created_at    DATE NOT NULL,
    is_published  BOOLEAN NOT NULL,
    CONSTRAINT fk_course_instructor
        FOREIGN KEY (instructor_id)
        REFERENCES online_courses.instructor (instructor_id),
    CONSTRAINT chk_course_level
        CHECK (level IN ('beginner', 'intermediate', 'advanced')),
    CONSTRAINT chk_course_price
        CHECK (price >= 0)
);

CREATE TABLE online_courses.lesson (
    lesson_id       INT PRIMARY KEY,
    course_id       INT NOT NULL,
    title           VARCHAR(200) NOT NULL,
    lesson_no       INT NOT NULL,
    duration_min    INT NOT NULL,
    is_free_preview BOOLEAN NOT NULL,
    CONSTRAINT fk_lesson_course
        FOREIGN KEY (course_id)
        REFERENCES online_courses.course (course_id),
    CONSTRAINT chk_lesson_no
        CHECK (lesson_no > 0),
    CONSTRAINT chk_lesson_duration
        CHECK (duration_min > 0),
    CONSTRAINT uq_lesson_course_no
        UNIQUE (course_id, lesson_no)
);

CREATE TABLE online_courses.enrollment (
    user_id             INT NOT NULL,
    course_id           INT NOT NULL,
    enrolled_at         DATE NOT NULL,
    progress_percentage NUMERIC(5, 2) NOT NULL,
    completion_status   VARCHAR(20) NOT NULL,
    last_access_at      TIMESTAMP,
    CONSTRAINT pk_enrollment
        PRIMARY KEY (user_id, course_id),
    CONSTRAINT fk_enrollment_user
        FOREIGN KEY (user_id)
        REFERENCES online_courses.user (user_id),
    CONSTRAINT fk_enrollment_course
        FOREIGN KEY (course_id)
        REFERENCES online_courses.course (course_id),
    CONSTRAINT chk_enrollment_progress
        CHECK (progress_percentage BETWEEN 0 AND 100),
    CONSTRAINT chk_enrollment_status
        CHECK (completion_status IN ('active', 'completed', 'dropped'))
);

CREATE TABLE online_courses.payment (
    payment_id     INT PRIMARY KEY,
    user_id        INT NOT NULL,
    course_id      INT NOT NULL,
    amount         NUMERIC(10, 2) NOT NULL,
    payment_status VARCHAR(20) NOT NULL,
    paid_at        TIMESTAMP NOT NULL,
    CONSTRAINT fk_payment_user
        FOREIGN KEY (user_id)
        REFERENCES online_courses.user (user_id),
    CONSTRAINT fk_payment_course
        FOREIGN KEY (course_id)
        REFERENCES online_courses.course (course_id),
    CONSTRAINT chk_payment_amount
        CHECK (amount > 0),
    CONSTRAINT chk_payment_status
        CHECK (payment_status IN ('pending', 'completed', 'failed', 'refunded'))
);

CREATE TABLE online_courses.review (
    review_id   INT PRIMARY KEY,
    user_id     INT NOT NULL,
    course_id   INT NOT NULL,
    rating      INT NOT NULL,
    review_text TEXT,
    review_data DATE NOT NULL,
    updated_at  TIMESTAMP,
    CONSTRAINT fk_review_user
        FOREIGN KEY (user_id)
        REFERENCES online_courses.user (user_id),
    CONSTRAINT fk_review_course
        FOREIGN KEY (course_id)
        REFERENCES online_courses.course (course_id),
    CONSTRAINT chk_review_rating
        CHECK (rating BETWEEN 1 AND 5),
    CONSTRAINT uq_review_user_course
        UNIQUE (user_id, course_id)
);

CREATE TABLE online_courses.certificate (
    certificate_id INT PRIMARY KEY,
    user_id        INT NOT NULL,
    course_id      INT NOT NULL,
    issued_at      DATE NOT NULL,
    CONSTRAINT fk_certificate_user
        FOREIGN KEY (user_id)
        REFERENCES online_courses.user (user_id),
    CONSTRAINT fk_certificate_course
        FOREIGN KEY (course_id)
        REFERENCES online_courses.course (course_id),
    CONSTRAINT uq_certificate_user_course
        UNIQUE (user_id, course_id)
);

CREATE TABLE online_courses.message (
    message_id INT PRIMARY KEY,
    user_id    INT NOT NULL,
    course_id  INT NOT NULL,
    content    TEXT NOT NULL,
    sent_at    TIMESTAMP NOT NULL,
    CONSTRAINT fk_message_user
        FOREIGN KEY (user_id)
        REFERENCES online_courses.user (user_id),
    CONSTRAINT fk_message_course
        FOREIGN KEY (course_id)
        REFERENCES online_courses.course (course_id)
);
