<?php
session_start();
include("connect.php");
if(isset($_POST['submit'])){
    $email = $_POST['email'];
    $password = $_POST['password'];

    $_SESSION["password"] = $password;

    if(!empty($email) && !empty($password)){

        $query = "select * from registered where email = '$email' limit 1";
        $result = mysqli_query($conn, $query);

        if($result)
        {
            if($result && mysqli_num_rows($result) > 0)
            {

                $user_data = mysqli_fetch_assoc($result);

                if($user_data['password'] === $password)
                {

                    $_SESSION['user_id'] = $user_data['user_id'];
                    $_SESSION['first_name'] = $user_data['first_name'];
                    $_SESSION['is_admin'] = $user_data['is_admin'];
                    if($user_data['is_admin'] == 1){
                        header("Location: home.php");
                    }else{
                        header("Location: dashboard2.php");
                    }
                    die;
        }
        
    }
}

}
}
?>

<link href="//maxcdn.bootstrapcdn.com/bootstrap/4.0.0/css/bootstrap.min.css" rel="stylesheet" id="bootstrap-css">
<script src="//maxcdn.bootstrapcdn.com/bootstrap/4.0.0/js/bootstrap.min.js"></script>
<script src="//code.jquery.com/jquery-1.11.1.min.js"></script>

<style type="text/css">
/* Body Font */
body {
    font-family: "Lato", sans-serif;
    height: 100vh; /* Set full viewport height */
    margin: 0;
    display: flex;
}

/* Sidenav Styling */
.sidenav {
    height: 100%;
    width: 40%; /* Occupy 40% of the width */
    background-color: #000;
    background-image: url(images/5.jpg);
    background-position: center;
    background-size: cover;
    color: #fff;
    display: flex;
    justify-content: center;
    align-items: center;
}

/* Main container to center the login form */
.main {
    width: 60%; /* Occupy the remaining 60% */
    display: flex;
    justify-content: center;
    align-items: center;
    padding: 0 20px; /* Add some padding */
}

/* Box Styling Around Login Form */
.login-form-box {
    background-color: #f9f9f9; /* Light background */
    padding: 40px;
    border-radius: 10px;
    box-shadow: 0px 0px 20px rgba(0, 0, 0, 0.1); /* Shadow to give a card-like effect */
    width: 100%;
    max-width: 400px;
}

/* Button Styling */
.btn-black {
    background-color: #000 !important;
    color: #fff;
    width: 100%; /* Full-width button */
    padding: 10px;
    border-radius: 5px;
    font-weight: bold;
}

/* Text Style in the Sidenav */
.login-main-text {
    text-align: center;
}

.login-main-text h2 {
    font-size: 2em;
    font-weight: bold;
}

.login-main-text p {
    font-size: 1em;
    margin-top: 15px;
}

@media screen and (max-width: 768px) {
    .sidenav {
        display: none; /* Hide sidenav on smaller screens */
    }
    .main {
        width: 100%; /* Take full width on smaller screens */
        padding: 0 10px;
    }
}
</style>

<!-- HTML Structure -->
<div class="sidenav">
    <div class="login-main-text">
        <h2><b>LOGIN TO TAXEASE</b></h2>
        <p class="mb-0">Don't have an account? <a href="signup.php" class="text-white-50 fw-bold">Sign Up</a></p>
    </div>
</div>

<div class="main">
    <div class="login-form-box">
        <!-- Login Form Inside a Card Box -->
        <form name="form" action="login.php" method="POST">
            <div class="form-group">
                <label>Email</label>
                <input type="email" name="email" class="form-control" placeholder="email" required>
            </div>
            <div class="form-group">
                <label>Password</label>
                <input type="password" name="password" class="form-control" placeholder="password" required>
            </div>
            <button type="submit" class="btn btn-black" name="submit">Login</button>
        </form>
    </div>
</div>
