<?php
    // connect database
    session_start();
    $conn = new PDO("mysql:host=localhost;dbname=taxease", "root", "");
    // check if FAQ existed
    if (!isset($_SESSION['user_id'])) {
        // Redirect to login if not logged in
        header("Location: login.php");
        exit();
    }
    
    $sql = "SELECT * FROM faqs WHERE id = ?";
    $statement = $conn->prepare($sql);
    $statement->execute([
        $_REQUEST["id"]
    ]);
    $faq = $statement->fetch();
    if (!$faq)
    {
        die("FAQ not found");
    }
    // delete from database
    $sql = "DELETE FROM faqs WHERE id = ?";
    $statement = $conn->prepare($sql);
    $statement->execute([
        $_POST["id"]
    ]);
    // redirect to previous page
    header("Location: add.php");
?>