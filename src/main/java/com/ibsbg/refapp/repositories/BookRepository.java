package com.ibsbg.refapp.repositories;

import java.util.List;

import com.ibsbg.refapp.entities.Book;
import org.springframework.data.jpa.repository.JpaRepository;

public interface BookRepository extends JpaRepository<Book, Long> {
  List<Book> findByPublished(boolean published);

  List<Book> findByTitleContaining(String title);
}