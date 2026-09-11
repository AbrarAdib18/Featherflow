<?php
// connect with database
session_start();
$conn = new PDO("mysql:host=localhost;dbname=tax", "root", "");
// fetch all FAQs from database
if (!isset($_SESSION['user_id'])) {
    // Redirect to login if not logged in
    header("Location: login.php");
    exit();
}
$sql = "SELECT * FROM faqs";
$statement = $conn->prepare($sql);
$statement->execute();
$faqs = $statement->fetchAll();
?>
<!-- include CSS -->
<link rel="stylesheet" type="text/css" href="css/bootstrap.css" />
<link rel="stylesheet" type="text/css" href="font-awesome/css/font-awesome.css" />
<!-- include JS -->
<script src="js/jquery-3.3.1.min.js"></script>
<script src="js/bootstrap.js"></script>

<!-- show all FAQs in a panel -->
<div class="container" style="margin-top: 50px; margin-bottom: 50px;">
    <div class="row">
        <div class="col-md-12 accordion_one">
            <div class="panel-group">
                <?php foreach ($faqs as $faq): ?>
                    <div class="panel panel-default">
                        <!-- button to show the question -->
                        <div class="panel-heading">
                            <h4 class="panel-title">
                                <a data-toggle="collapse" data-parent="#accordion_oneLeft" href="#faq-<?php echo $faq['id']; ?>" aria-expanded="false" class="collapsed">
                                    <?php echo $faq['question']; ?>
                                </a>
                            </h4>
                        </div>
                        <!-- accordion for answer -->
                        <div id="faq-<?php echo $faq['id']; ?>" class="panel-collapse collapse" aria-expanded="false" role="tablist" style="height: 0px;">
                            <div class="panel-body">
                                <div class="text-accordion">
                                    <?php echo $faq['answer']; ?>
                                </div>
                            </div>
                        </div>
                    </div>
                <?php endforeach; ?>
            </div>
        </div>
    </div>
</div>

<style>
    body {
        background-color: #0d0d0d; /* Dark background */
        color: #f5f5f5; /* Light text for general content */
        font-family: 'Open Sans', sans-serif; /* Font styling */
    }

    .accordion_one .panel-group {
        margin-top: 50px;
        border-radius: 8px; /* Rounded corners for the accordion */
        overflow: hidden; /* Prevents border-radius issues */
    }

    .accordion_one .panel {
        background-color: #1c1c1c; /* Dark panel background */
        border: none; /* No border */
        margin-bottom: 15px; /* Space between panels */
        border-radius: 8px; /* Rounded edges for the boxes */
    }

    .accordion_one .panel-heading {
        background: #000; /* Black background for heading */
        border-bottom: 1px solid #444; /* Bottom border */
        border-radius: 8px; /* Rounded edges for question box */
        padding: 10px 20px; /* Reduced padding for compact look */
        margin: 0; /* No margin */
    }

    .accordion_one .panel-heading a {
        display: block;
        color: #fff; /* White text */
        font-size: 16px; /* Font size */
        transition: background 0.3s; /* Transition for hover effect */
    }

    .accordion_one .panel-heading a:hover {
        background: #404040; /* Darker background on hover */
    }

    .accordion_one .panel-collapse {
        border-top: 1px solid #444; /* Border at the top of the body */
    }

    .accordion_one .panel .panel-body {
        padding: 15px 20px; /* Body padding */
        background: #ffffff; /* White background for answers */
        color: #000000; /* Black text for answers */
        border-radius: 8px; /* Rounded edges for the answer box */
        margin: 0; /* Remove margin to align with the left */
    }

    .accordion_one .panel .panel-body {
        margin-left: 0; /* Align the answer box with the left */
    }

    .accordion_one .panel .panel-heading a.collapsed:after {
        content: "\2b"; /* Plus sign for collapsed */
        color: #999; /* Color for plus sign */
    }

    .accordion_one .panel .panel-heading a:after {
        content: "\2212"; /* Minus sign for expanded */
        color: #fff; /* White color for minus sign */
    }
</style>
