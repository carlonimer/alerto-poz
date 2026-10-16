-- Migration: Allow incidents.category to be NULL for draft emergency reports
-- Problem: MySQL rejects saving drafts before a category is chosen with "Column 'category' cannot be null"
-- Fix: Make incidents.category column NULLable

ALTER TABLE incidents MODIFY COLUMN category VARCHAR(50) NULL;
