CREATE DATABASE movierms;
USE movierms;

-- Creating tables

-- Users table
CREATE TABLE Users (
    user_id INT PRIMARY KEY,
    age INT,
    gender CHAR(1),
    occupation VARCHAR(50),
    zip_code VARCHAR(20)
);

-- Genres table
CREATE TABLE Genres (
    genre_id INT PRIMARY KEY,
    genre_name VARCHAR(50)
);

-- Movies table
CREATE TABLE Movies (
    movie_id INT PRIMARY KEY,
    title VARCHAR(255),
    release_date DATE,
    video_release_date VARCHAR(50),
    imdb_url VARCHAR(255)
    -- NOTE: The 19 genre flags are not included here; 
    -- if needed we join via a mapping table.
);

-- Ratings table
CREATE TABLE Ratings (
    rating_id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT,
    movie_id INT,
    rating DECIMAL(2,1),
    rating_timestamp BIGINT,
    FOREIGN KEY (user_id) REFERENCES Users(user_id),
    FOREIGN KEY (movie_id) REFERENCES Movies(movie_id)
);

-- Load Users
LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/users.xls'
INTO TABLE Users
FIELDS TERMINATED BY ','
IGNORE 1 ROWS
(user_id, age, gender, occupation, zip_code);


-- Load Genres
LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/genres.xls'
INTO TABLE Genres
FIELDS TERMINATED BY ',' 
IGNORE 1 ROWS
(genre_name, genre_id);

-- Load Movies
LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/movies.xls'
INTO TABLE Movies
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
IGNORE 1 ROWS
(movie_id, title, @release_date, video_release_date, imdb_url,
 @dummy1, @dummy2, @dummy3, @dummy4, @dummy5,
 @dummy6, @dummy7, @dummy8, @dummy9, @dummy10,
 @dummy11, @dummy12, @dummy13, @dummy14, @dummy15,
 @dummy16, @dummy17, @dummy18, @dummy19)
SET release_date = CASE
    WHEN @release_date = '' THEN NULL
    ELSE STR_TO_DATE(@release_date, '%d-%b-%Y')
END;



-- Load Ratings
LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/ratings.xls'
INTO TABLE Ratings
FIELDS TERMINATED BY ',' 
IGNORE 1 ROWS
(user_id, movie_id, rating, rating_timestamp);

set sql_safe_updates = 0;
SHOW VARIABLES LIKE 'secure_file_priv';

-- The 19 genre flags are not stored here anymore — instead, the MovieGenres mapping table
CREATE TABLE MovieGenres (
    movie_id INT,
    genre_id INT,
    PRIMARY KEY (movie_id, genre_id),
    FOREIGN KEY (movie_id) REFERENCES Movies(movie_id),
    FOREIGN KEY (genre_id) REFERENCES Genres(genre_id)
);

LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/movie_genres.xls'
INTO TABLE MovieGenres
FIELDS TERMINATED BY ','
IGNORE 1 ROWS
(movie_id, genre_id);
set sql_safe_updates =  0;

-- COUNTING ROWS IN EACH TABLE 
SELECT COUNT(*) FROM Users;
SELECT COUNT(*) FROM Movies;
SELECT COUNT(*) FROM Ratings;
SELECT COUNT(*) FROM Genres;
SELECT COUNT(*) FROM MovieGenres;

-- QUICK PREVIEW WITH JOINS 
SELECT r.user_id, m.title, r.rating
FROM Ratings r
JOIN Movies m ON r.movie_id = m.movie_id
LIMIT 10;

-- DESCRIPTIVE INSIGHTS 
-- >Top 10 most-rated movies.
-- >Average rating per genre.
-- >User preferences by demographics.
-- >Measure if older or newer movies got more attention.
-- >This avoids small-sample bias.
-- >Comparing a movie’s rating to the average of its genre.
-- >Ranking the movies each user rated by timestamp (first watched → latest watched).

SELECT m.title, COUNT(r.rating) AS num_ratings
FROM Ratings r
JOIN Movies m ON r.movie_id = m.movie_id
GROUP BY m.title
ORDER BY num_ratings DESC
LIMIT 10;

SELECT g.genre_name, AVG(r.rating) AS avg_rating
FROM Ratings r
JOIN MovieGenres mg ON r.movie_id = mg.movie_id
JOIN Genres g ON mg.genre_id = g.genre_id
GROUP BY g.genre_name
ORDER BY avg_rating DESC;

SELECT 
    CASE 
        WHEN u.age < 18 THEN 'Teen'
        WHEN u.age BETWEEN 18 AND 29 THEN 'Young Adult'
        WHEN u.age BETWEEN 30 AND 44 THEN 'Adult'
        ELSE 'Senior'
    END AS age_group,
    AVG(r.rating) AS avg_rating
FROM Ratings r
JOIN Users u ON r.user_id = u.user_id
GROUP BY age_group
ORDER BY avg_rating DESC;

SELECT YEAR(m.release_date) AS release_year,
       COUNT(r.rating) AS total_ratings,
       AVG(r.rating) AS avg_rating
FROM Ratings r
JOIN Movies m ON r.movie_id = m.movie_id
WHERE m.release_date IS NOT NULL
GROUP BY release_year
ORDER BY release_year;

SELECT m.title, AVG(r.rating) AS avg_rating, COUNT(r.rating) AS total_ratings
FROM Ratings r
JOIN Movies m ON r.movie_id = m.movie_id
GROUP BY m.movie_id, m.title
HAVING COUNT(r.rating) >= 100
ORDER BY avg_rating DESC
LIMIT 10;

SELECT g.genre_name,
       m.title,
       AVG(r.rating) AS movie_avg,
       AVG(AVG(r.rating)) OVER (PARTITION BY g.genre_name) AS genre_avg,
       AVG(r.rating) - AVG(AVG(r.rating)) OVER (PARTITION BY g.genre_name) AS diff_from_genre
FROM Ratings r
JOIN Movies m ON r.movie_id = m.movie_id
JOIN MovieGenres mg ON m.movie_id = mg.movie_id
JOIN Genres g ON mg.genre_id = g.genre_id
GROUP BY g.genre_name, m.movie_id, m.title;

SELECT r.user_id,
       m.title,
       r.rating,
       r.rating_timestamp,
       ROW_NUMBER() OVER (PARTITION BY r.user_id ORDER BY r.rating_timestamp) AS watch_order
FROM Ratings r
JOIN Movies m ON r.movie_id = m.movie_id;

-- #### Global average rating C
SELECT AVG(rating) AS C FROM Ratings;

-- movie counts + mean
CREATE OR REPLACE VIEW movie_stats AS
SELECT 
  m.movie_id,
  m.title,
  COUNT(r.rating) AS v,
  AVG(r.rating) AS R
FROM Movies m
LEFT JOIN Ratings r ON m.movie_id = r.movie_id
GROUP BY m.movie_id, m.title;

-- Bayesian score with prior m (minimum votes)
-- score = (v/(v+m))*R + (m/(v+m))*C
SELECT *, 
  (v / (v + 50.0)) * R + (50.0 / (v + 50.0)) * (SELECT AVG(rating) FROM Ratings) AS bayes_score
FROM movie_stats
ORDER BY bayes_score DESC
LIMIT 20;

#computing user's genre preference

CREATE OR REPLACE VIEW user_genre_score AS
SELECT 
  r.user_id,
  mg.genre_id,
  g.genre_name,
  AVG(r.rating) AS avg_rating,
  COUNT(*) AS cnt
FROM Ratings r
JOIN MovieGenres mg ON r.movie_id = mg.movie_id
JOIN Genres g ON mg.genre_id = g.genre_id
GROUP BY r.user_id, mg.genre_id, g.genre_name;



